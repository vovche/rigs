using GLib.Intl;

/* compose_driver.vala — a compose project directory (podman/docker compose up/down,
 * or the user's start_cmd/stop_cmd). Status: the container named container_name. */
namespace Rigs {
    public class ComposeDriver : Object, Driver {
        // Milliseconds to wait before checking whether the container exited at once.
        public uint settle_ms = 2000;

        public ResourceKind kind { get { return ResourceKind.COMPOSE; } }

        private HostCommand host;

        public ComposeDriver(HostCommand? host = null) {
            this.host = host ?? new HostCommand();
        }

        private static string? directory_of(Resource resource) {
            return resource.dir.length > 0 ? resource.dir : null;
        }

        public ResourceIssue? start(Resource resource) {
            string[] argv = resource.start_cmd.length > 0
                ? new string[] { "/bin/bash", "-c", resource.start_cmd }
                : new string[] { resource.runtime.command(), "compose", "up", "-d" };
            try {
                var result = host.run_capture_tail(argv, directory_of(resource));
                if (result.exit_status != 0)
                    return FailureRules.diagnose_container(host, resource.runtime, resource.container_name, result, resource.guest_os);
                // Without container_name the services cannot be checked after `up -d` (see docs/guardrails.md).
                if (resource.container_name.length == 0) return null;
                if (settle_ms > 0) Thread.usleep(settle_ms * 1000);
                if (FailureRules.container_exited(host, resource.runtime, resource.container_name))
                    return FailureRules.diagnose_container(host, resource.runtime, resource.container_name, null, resource.guest_os);
            } catch (Error e) {
                return ResourceIssue.from_error(e);
            }
            return null;
        }

        public ResourceIssue? stop(Resource resource) {
            string[] argv = resource.stop_cmd.length > 0
                ? new string[] { "/bin/bash", "-c", resource.stop_cmd }
                : new string[] { resource.runtime.command(), "compose", "down" };
            return FailureRules.check_command(host, argv, directory_of(resource), 120000);
        }

        public ResourceIssue? open_console(Resource resource) {
            if (resource.connect_cmd.length == 0)
                return ResourceIssue.unsupported(_("No connect command is configured for this resource."));
            return FailureRules.check_command(host, { "/bin/bash", "-c", resource.connect_cmd }, directory_of(resource));
        }

        public ResourceIssue? insert_iso(Resource resource, string iso_path) {
            return ResourceIssue.unsupported(_("Compose resources have no optical drive control."));
        }

        public ResourceIssue? eject_iso(Resource resource) {
            return insert_iso(resource, "");
        }

        public ResourceStatus check_status(Resource resource) {
            ResourceStatus st = ResourceStatus();
            st.ram_str = "0 MB";
            if (resource.container_name.length == 0 || resource.container_name.has_prefix("-")) return st;
            try {
                var result = host.run({resource.runtime.command(), "inspect", "--format", "{{.State.Running}}", resource.container_name});
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
                    string template = resource.runtime == ContainerRuntime.PODMAN ? "{{.CPU}}\t{{.MemUsage}}" : "{{.CPUPerc}}\t{{.MemUsage}}";
                    result = host.run({resource.runtime.command(), "stats", "--no-stream", "--format", template, resource.container_name});
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

    }
}
