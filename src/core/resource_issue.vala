using GLib.Intl;

/* resource_issue.vala — deterministic, rule-based analysis of resource startup failures. */
namespace Rigs {
    public enum FailureCategory {
        STORAGE_MOUNT,
        NETWORK_PORT,
        CONTAINER_CONFLICT,
        PERMISSIONS_KVM,
        RESOURCE_EXHAUSTION,
        MISSING_PROGRAM,
        TIMEOUT,
        UNSUPPORTED,
        GENERIC_ERROR
    }

    // What the user asked for when the failure happened; selects the headline wording.
    public enum ResourceOperation {
        START,
        STOP,
        CONNECT,
        MEDIA,
        // The resource was running and its start command exited with an error later.
        RUN
    }

    public class ResourceIssue : Object {
        public FailureCategory category { get; set; default = FailureCategory.GENERIC_ERROR; }
        public ResourceOperation operation { get; set; default = ResourceOperation.START; }
        public string title { get; set; default = ""; }
        public string description { get; set; default = ""; }
        // Human-readable advice (may mention a command in backticks).
        public string? suggested_action { get; set; default = null; }
        // Copy-pasteable shell command, only when one is safe and specific.
        public string? suggested_command { get; set; default = null; }
        public string? matched_snippet { get; set; default = null; }
    }

    public class FailureRules : Object {
        private const int MAX_INPUT = 65536;
        // Nonzero exits of long-running user commands (foreground QEMU, viewers) count
        // as start/connect failures only this soon after launch; later ones are RUN issues.
        public const int64 STARTUP_WINDOW_US = 60 * 1000000;
        private const int MAX_SNIPPET = 400;

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
                warning("Invalid diagnostics pattern: %s", e.message);
                return null;
            }
        }

        private static ResourceIssue make(FailureCategory category, string title, string description,
                string? action, string? command, string? snippet) {
            var issue = new ResourceIssue();
            issue.category = category;
            issue.title = title;
            issue.description = description;
            issue.suggested_action = action;
            issue.suggested_command = command;
            issue.matched_snippet = snippet;
            return issue;
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
                return make(FailureCategory.CONTAINER_CONFLICT, _("A container with this name already exists"),
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
                return make(FailureCategory.STORAGE_MOUNT, _("Mount directory not found"),
                    _("The path “%s” is mounted into the resource but does not exist on the host.").printf(found[0]),
                    _("Create the directory with `%s` or check the paths in compose.yaml.").printf(command), command, snippet);
            }

            found = search("rootless netns: kill network process: permission denied", text, {}, out snippet);
            if (found != null) {
                return make(FailureCategory.NETWORK_PORT, _("Rootless Podman networking is stuck"),
                    _("A leftover network process from an earlier run blocks the rootless network namespace."),
                    _("End the stale netns processes, or as a last resort run `podman system reset` (this removes all Podman containers and images)."),
                    null, snippet);
            }

            found = search("Could not access KVM kernel module|/dev/kvm: Permission denied", text, {}, out snippet);
            if (found != null) {
                string command = "sudo usermod -aG kvm $USER";
                return make(FailureCategory.PERMISSIONS_KVM, _("No access to KVM acceleration"),
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
                return make(FailureCategory.NETWORK_PORT, _("Network port is already in use"),
                    port == "<port>" ? _("Another process already listens on a port this resource needs.")
                        : _("Another process already listens on port %s, which this resource needs.").printf(port),
                    _("Find the process with `%s` or change the port in the configuration.").printf(command), command, snippet);
            }

            found = search("OOMKilled|cannot allocate memory", text, {}, out snippet);
            if (found != null) {
                string hint = guest_os == "windows"
                    ? _("Reduce the VM memory in its configuration; Windows guests usually need at least 4 GB.")
                    : _("Reduce the memory allocated in the VM configuration.");
                return make(FailureCategory.RESOURCE_EXHAUSTION, _("Not enough memory"),
                    _("The host ran out of memory while starting the resource."), hint, null, snippet);
            }

            // No known rule: surface the last meaningful line instead of hiding the failure.
            string last = "";
            foreach (string line in text.split("\n")) if (line.strip().length > 0) last = line.strip();
            if (last.length > MAX_SNIPPET) last = last.substring(0, MAX_SNIPPET) + "…";
            return make(FailureCategory.GENERIC_ERROR, _("Startup failed"),
                _("The resource did not start and the cause is not a known one."),
                _("Check the output below for details."), null, last);
        }

        private static bool usable_name(string name) {
            return name.length > 0 && !name.has_prefix("-");
        }

        // Combines stderr/stdout, falls back to `logs --tail=30` for an exited container, then classifies.
        public static ResourceIssue? diagnose(HostCommand host, string runtime, string container,
                CommandResult? result, string? guest_os = null) {
            string text = result != null ? (result.error_output + "\n" + result.output).strip() : "";
            if (text.length == 0 && usable_name(container) && (runtime == "podman" || runtime == "docker")) {
                try {
                    var logs = host.run({ runtime, "logs", "--tail=30", container }, null, 10000);
                    text = (logs.error_output + "\n" + logs.output).strip();
                } catch (Error e) {
                    warning("Could not read container logs: %s", e.message);
                }
            }
            var issue = analyze(text, guest_os);
            if (issue == null && result != null && result.exit_status != 0) {
                issue = analyze(_("Command exited with status %d without any output").printf(result.exit_status), guest_os);
                if (issue != null) issue.matched_snippet = null;
            }
            return issue;
        }

        // True when the container exists and is no longer running shortly after a successful start.
        public static bool exited_after_start(HostCommand host, string runtime, string container) {
            if (!usable_name(container) || (runtime != "podman" && runtime != "docker")) return false;
            try {
                var state = host.run({ runtime, "inspect", "--format", "{{.State.Running}}", container });
                return state.exit_status == 0 && state.output.strip() == "false";
            } catch (Error e) {
                return false;
            }
        }

        // One headline per operation, shared by the toast, the card tooltip and the dialog.
        public static string headline(ResourceOperation operation, string name) {
            switch (operation) {
                case ResourceOperation.STOP: return _("Failed to stop %s").printf(name);
                case ResourceOperation.CONNECT: return _("Could not connect to %s").printf(name);
                case ResourceOperation.MEDIA: return _("Could not change the optical media of %s").printf(name);
                case ResourceOperation.RUN: return _("%s stopped with an error").printf(name);
                default: return _("Failed to start %s").printf(name);
            }
        }

        // An exception from HostCommand/GIO (program missing, timeout, unsupported package) as an issue.
        public static ResourceIssue from_error(Error e, ResourceOperation operation = ResourceOperation.START) {
            ResourceIssue issue;
            if (e.matches(IOError.quark(), IOError.TIMED_OUT)) {
                issue = make(FailureCategory.TIMEOUT, _("The command timed out"),
                    _("The command did not finish within its time limit."),
                    _("Run the command in a terminal to see where it stops."), null, e.message);
            } else if (e.matches(SpawnError.quark(), SpawnError.NOENT) ||
                       e.matches(IOError.quark(), IOError.NOT_FOUND)) {
                issue = make(FailureCategory.MISSING_PROGRAM, _("Program not found"),
                    _("A program this resource needs is not installed or not in PATH."),
                    _("Install the missing program or fix the command in the resource settings."), null, e.message);
            } else if (e.matches(IOError.quark(), IOError.NOT_SUPPORTED)) {
                issue = make(FailureCategory.UNSUPPORTED, _("Not supported in this installation"),
                    e.message, _("Use the native package for this kind of resource."), null, null);
            } else {
                issue = make(FailureCategory.GENERIC_ERROR, _("The operation failed"),
                    _("Rigs could not run the command for this resource."),
                    _("Check the output below for details."), null, e.message);
            }
            issue.operation = operation;
            return issue;
        }

        // The command finished without an error, yet the resource is not running.
        public static ResourceIssue not_running(string detail, string? suggested_command = null) {
            return make(FailureCategory.GENERIC_ERROR, _("The resource stopped right after start"),
                _("The start command finished, but the resource is not running."),
                suggested_command != null ? _("Inspect it with `%s`.").printf(suggested_command)
                                          : _("Check the output below for details."),
                suggested_command, detail);
        }

        // Runs a user-configured command and turns a nonzero exit or an exception into an issue.
        // timeout_ms == 0: long-running command (viewer, foreground VM) via run_capture_tail.
        public static ResourceIssue? check_command(HostCommand host, string[] argv, string? directory,
                ResourceOperation operation, uint timeout_ms = 0) {
            try {
                var result = timeout_ms == 0 ? host.run_capture_tail(argv, directory)
                                             : host.run(argv, directory, timeout_ms);
                if (result.exit_status == 0) return null;
                var issue = diagnose(host, "", "", result);
                if (issue != null) issue.operation = operation;
                return issue;
            } catch (Error e) {
                return from_error(e, operation);
            }
        }

        // The only way drivers run work off the main thread: whatever the job
        // returns is published, so a failure cannot be dropped on the floor.
        public delegate ResourceIssue? Job();

        public static void run_in_background(Resource resource, string thread_name, owned Job job) {
            new Thread<void*>(thread_name, () => {
                ResourceIssue? issue = job();
                if (issue != null) publish(resource, issue);
                return null;
            });
        }

        // Safe from worker threads: model changes happen on the main context.
        public static void publish(Resource resource, ResourceIssue issue) {
            Idle.add(() => {
                resource.last_issue = issue;
                resource.issue_raised(issue);
                return false;
            });
        }
    }
}
