using GLib.Intl;

/* failure_rules.vala — turns command output into a ResourceIssue, deterministically.
 * analyze() is pure (regex rules over text); the other helpers run bounded host commands.
 * Adding a rule: add a test with the runtime's exact wording (docs/guardrails.md). */
namespace Rigs {
    public class FailureRules : Object {
        private const int MAX_INPUT = 65536;
        private const int MAX_SNIPPET = 400;
        // Nonzero exits of long-running user commands (foreground QEMU, viewers) count
        // as start/connect failures only this soon after launch; later ones are RUN issues.
        public const int64 STARTUP_WINDOW_US = 60 * 1000000;

        // Returns the captured named groups (in `names` order) of the first match, or null.
        private static string[]? search(string pattern, string text, string[] names, out string snippet) {
            snippet = "";
            try {
                var regex = new Regex(pattern, RegexCompileFlags.CASELESS | RegexCompileFlags.OPTIMIZE);
                MatchInfo info;
                if (!regex.match(text, 0, out info)) return null;
                int start, end;
                info.fetch_pos(0, out start, out end);
                int line_start = text.substring(0, start).last_index_of_char('\n') + 1;
                int line_end = text.index_of_char('\n', end);
                if (line_end < 0) line_end = text.length;
                snippet = text.substring(line_start, line_end - line_start).strip();
                if (snippet.length > MAX_SNIPPET) snippet = snippet.substring(0, MAX_SNIPPET) + "…";
                string[] values = {};
                foreach (string name in names) values += (info.fetch_named(name) ?? "").strip();
                return values;
            } catch (RegexError e) {
                // Patterns are constants covered by tests; a broken one must fail loudly there.
                critical("Invalid diagnostics pattern: %s", e.message);
                return null;
            }
        }

        public static ResourceIssue? analyze(string raw_output, string? guest_os = null) {
            string text = raw_output.strip();
            if (text.length == 0) return null;
            if (text.length > MAX_INPUT) text = text.substring(text.length - MAX_INPUT);
            string snippet;
            string[]? found;

            found = search("name \\\\?\"(?<name>[^\"\\\\]+)\\\\?\" is already in use by (?:container )?\\\\?\"?(?<id>[a-f0-9]+)", text,
                { "name", "id" }, out snippet);
            if (found != null) {
                string tool = text.contains("Conflict. The container name") || text.down().contains("docker") ? "docker" : "podman";
                string name = found[0].has_prefix("/") ? found[0].substring(1) : found[0];
                string command = "%s rm -f %s".printf(tool, found[1]);
                return new ResourceIssue(FailureCategory.CONTAINER_CONFLICT, _("A container with this name already exists"),
                    _("The name “%s” is already taken by container %s, so a new one cannot be created.").printf(name, found[1]),
                    _("Remove the old container with `%s` or rename this one.").printf(command), command, snippet);
            }

            found = search("cannot stat '(?<path>[^']+)': No such file", text, { "path" }, out snippet);
            if (found == null)
                found = search("bind source path does not exist: *(?<path>[^\\n]+)", text, { "path" }, out snippet);
            // Rootless Podman (the most common runtime here) reports a missing bind source via statfs.
            if (found == null)
                found = search("statfs (?<path>/[^:\\n]+): no such file or directory", text, { "path" }, out snippet);
            if (found != null) {
                string command = "mkdir -p " + Shell.quote(found[0]);
                return new ResourceIssue(FailureCategory.STORAGE_MOUNT, _("Mount directory not found"),
                    _("The path “%s” is mounted into the resource but does not exist on the host.").printf(found[0]),
                    _("Create the directory with `%s` or check the paths in compose.yaml.").printf(command), command, snippet);
            }

            found = search("rootless netns: kill network process: permission denied", text, {}, out snippet);
            if (found != null) {
                return new ResourceIssue(FailureCategory.NETWORK_PORT, _("Rootless Podman networking is stuck"),
                    _("A leftover network process from an earlier run blocks the rootless network namespace."),
                    _("End the stale netns processes, or as a last resort run `podman system reset` (this removes all Podman containers and images)."),
                    null, snippet);
            }

            found = search("Could not access KVM kernel module|/dev/kvm: Permission denied", text, {}, out snippet);
            if (found != null) {
                string command = "sudo usermod -aG kvm $USER";
                return new ResourceIssue(FailureCategory.PERMISSIONS_KVM, _("No access to KVM acceleration"),
                    _("The current user may not use /dev/kvm, so hardware virtualization cannot start."),
                    _("Add yourself to the kvm group with `%s`, then log out and back in.").printf(command), command, snippet);
            }

            found = search("(?:address already in use|port is already allocated)", text, {}, out snippet);
            if (found != null) {
                string port = "<port>";
                string ignored;
                string[]? p = search("(?:[0-9.]+|\\[[0-9a-f:]*\\]|\\*):(?<port>\\d{1,5})\\b[^\\n]*(?:address already in use|port is already allocated)",
                    text, { "port" }, out ignored);
                if (p != null && p[0].length > 0) port = p[0];
                string command = "ss -tulpn | grep :" + port;
                return new ResourceIssue(FailureCategory.NETWORK_PORT, _("Network port is already in use"),
                    port == "<port>" ? _("Another process already listens on a port this resource needs.")
                        : _("Another process already listens on port %s, which this resource needs.").printf(port),
                    _("Find the process with `%s` or change the port in the configuration.").printf(command), command, snippet);
            }

            found = search("OOMKilled|cannot allocate memory", text, {}, out snippet);
            if (found != null) {
                string hint = guest_os == "windows"
                    ? _("Reduce the VM memory in its configuration; Windows guests usually need at least 4 GB.")
                    : _("Reduce the memory allocated in the VM configuration.");
                return new ResourceIssue(FailureCategory.RESOURCE_EXHAUSTION, _("Not enough memory"),
                    _("The host ran out of memory while starting the resource."), hint, null, snippet);
            }

            // No known rule: surface the last meaningful line instead of hiding the failure.
            string last = "";
            foreach (string line in text.split("\n")) if (line.strip().length > 0) last = line.strip();
            if (last.length > MAX_SNIPPET) last = last.substring(0, MAX_SNIPPET) + "…";
            return new ResourceIssue(FailureCategory.GENERIC_ERROR, _("Unrecognized error"),
                _("Rigs does not recognize the cause of this failure."),
                _("Check the output below for details."), null, last);
        }

        private static bool usable_name(string name) {
            return name.length > 0 && !name.has_prefix("-");
        }

        // Classifies a finished command; null when it succeeded.
        public static ResourceIssue? diagnose(CommandResult result, string? guest_os = null) {
            var issue = analyze((result.error_output + "\n" + result.output).strip(), guest_os);
            if (issue == null && result.exit_status != 0) {
                issue = analyze(_("Command exited with status %d without any output").printf(result.exit_status), guest_os);
                if (issue != null) issue.matched_snippet = null;
            }
            return issue;
        }

        // Like diagnose(), but a silent failure falls back to `<runtime> logs --tail=30 <container>`.
        // result == null: the container started and exited on its own (see container_exited).
        public static ResourceIssue? diagnose_container(HostCommand host, ContainerRuntime runtime, string container,
                CommandResult? result, string? guest_os = null) {
            string text = result != null ? (result.error_output + "\n" + result.output).strip() : "";
            if (text.length == 0 && usable_name(container)) {
                try {
                    var logs = host.run({ runtime.command(), "logs", "--tail=30", container }, null, 10000);
                    text = (logs.error_output + "\n" + logs.output).strip();
                } catch (Error e) {
                    text = e.message;
                }
            }
            if (text.length > 0) return analyze(text, guest_os);
            return result != null ? diagnose(result, guest_os)
                                  : analyze(_("The container exited without any output"), guest_os);
        }

        // True when the container exists and is no longer running shortly after a successful start.
        public static bool container_exited(HostCommand host, ContainerRuntime runtime, string container) {
            if (!usable_name(container)) return false;
            try {
                var state = host.run({ runtime.command(), "inspect", "--format", "{{.State.Running}}", container });
                return state.exit_status == 0 && state.output.strip() == "false";
            } catch (Error e) {
                return false;
            }
        }

        // Runs a user-configured command; a nonzero exit or an exception becomes an issue.
        // timeout_ms == 0: long-running command (viewer, foreground VM) via run_capture_tail.
        public static ResourceIssue? check_command(HostCommand host, string[] argv, string? directory,
                uint timeout_ms = 0) {
            try {
                var result = timeout_ms == 0 ? host.run_capture_tail(argv, directory)
                                             : host.run(argv, directory, timeout_ms);
                return result.exit_status == 0 ? null : diagnose(result);
            } catch (Error e) {
                return ResourceIssue.from_error(e);
            }
        }
    }
}
