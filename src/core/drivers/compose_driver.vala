/* compose_driver.vala — Explicitly configured compose projects. */
namespace Rigs {
    public class ComposeDriver : Object, Driver {
        private const uint SETTLE_MS = 2000;

        public string kind { get { return "compose"; } }

        private ResourceIssue? lifecycle_blocking(Resource resource, bool starting) {
            if (resource.runtime != "podman" && resource.runtime != "docker") return null;
            string cmd = starting ? resource.start_cmd : resource.stop_cmd;
            var host = new HostCommand();
            string? directory = resource.dir.length > 0 ? resource.dir : null;
            string[] argv;
            if (cmd.length > 0) argv = { "/bin/bash", "-c", cmd };
            else argv = starting ? new string[] { resource.runtime, "compose", "up", "-d" }
                                 : new string[] { resource.runtime, "compose", "down" };
            if (!starting)
                return FailureRules.check_command(host, argv, directory, ResourceOperation.STOP, 120000);
            try {
                var result = host.run_capture_tail(argv, directory);
                if (result.exit_status != 0)
                    return FailureRules.diagnose(host, resource.runtime, resource.container_name, result, resource.guest_os);
                // Without container_name the services cannot be checked after `up -d` (see docs/guardrails.md).
                Thread.usleep(SETTLE_MS * 1000);
                if (FailureRules.exited_after_start(host, resource.runtime, resource.container_name))
                    return FailureRules.diagnose(host, resource.runtime, resource.container_name, null, resource.guest_os);
            } catch (Error e) {
                return FailureRules.from_error(e);
            }
            return null;
        }

        public void start(Resource resource) {
            FailureRules.run_in_background(resource, "compose-start", () => lifecycle_blocking(resource, true));
        }

        public void stop(Resource resource) {
            FailureRules.run_in_background(resource, "compose-stop", () => lifecycle_blocking(resource, false));
        }

        public void open_console(Resource resource) {
            if (resource.connect_cmd.length == 0) return;
            FailureRules.run_in_background(resource, "compose-connect", () =>
                FailureRules.check_command(new HostCommand(), { "/bin/bash", "-c", resource.connect_cmd },
                    resource.dir.length > 0 ? resource.dir : null, ResourceOperation.CONNECT));
        }

        public ResourceStatus check_status(Resource resource) {
            ResourceStatus st = ResourceStatus();
            st.ram_str = "0 MB";
            if (resource.container_name.length == 0 || resource.container_name.has_prefix("-") ||
                (resource.runtime != "podman" && resource.runtime != "docker")) return st;
            try {
                var host = new HostCommand();
                var result = host.run({resource.runtime, "inspect", "--format", "{{.State.Running}}", resource.container_name});
                // A reachable runtime without this container means stopped, not unavailable: Start must stay usable.
                if (result.exit_status != 0 && is_missing_container(result)) {
                    st.status_available = true;
                    return st;
                }
                string state = result.output.strip();
                if (result.exit_status != 0 || (state != "true" && state != "false")) return st;
                st.status_available = true;
                st.running = state == "true";
                if (st.running) {
                    string template = resource.runtime == "podman" ? "{{.CPU}}\t{{.MemUsage}}" : "{{.CPUPerc}}\t{{.MemUsage}}";
                    result = host.run({resource.runtime, "stats", "--no-stream", "--format", template, resource.container_name});
                    if (result.exit_status == 0) {
                        var parts = result.output.strip().split("\t");
                        if (parts.length == 2) {
                            st.cpu_pct = Metrics.container_cpu_share(parts[0]);
                            st.ram_str = parts[1].split("/")[0].strip();
                        }
                    }
                }
            } catch (Error e) { }
            return st;
        }

        // Podman and Docker both report an absent container as "no such object" / "No such container".
        public static bool is_missing_container(CommandResult result) {
            return (result.output + result.error_output).down().contains("no such");
        }

        public void insert_iso(Resource resource, string iso_path) { }
        public void eject_iso(Resource resource) { }
    }
}
