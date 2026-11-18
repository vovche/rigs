using GLib.Intl;

/* container_driver.vala — one existing Podman/Docker container, addressed by its ID
 * (resource_id). Commands are fixed argv lists; nothing from the config reaches a shell
 * except the user's own connect_cmd. */
namespace Rigs {
    public class ContainerDriver : Object, Driver {
        private HostCommand commands;
        // Milliseconds to wait before checking whether a started container exited at once.
        public uint settle_ms = 2000;
        // 0 = host CPU count; tests pin it for deterministic percentages.
        public uint cpu_count = 0;

        public ResourceKind kind { get { return ResourceKind.CONTAINER; } }

        public ContainerDriver(HostCommand? commands = null) {
            this.commands = commands ?? new HostCommand();
        }

        public static bool valid_target(Resource resource) {
            return Regex.match_simple("^[a-fA-F0-9]{12,64}$", resource.resource_id);
        }

        // Public for deterministic lifecycle contract tests without starting real resources.
        public string[] lifecycle_argv(Resource resource, bool starting) {
            if (!valid_target(resource)) return {};
            if (starting) return { resource.runtime.command(), "start", resource.resource_id };
            return { resource.runtime.command(), "stop", "--time", "30", resource.resource_id };
        }

        private ResourceIssue invalid_target() {
            return ResourceIssue.unsupported(_("The container ID in this resource is not valid."));
        }

        public ResourceIssue? start(Resource resource) {
            string[] argv = lifecycle_argv(resource, true);
            if (argv.length == 0) return invalid_target();
            try {
                var result = commands.run(argv, null, 30000);
                if (result.exit_status != 0)
                    return FailureRules.diagnose_container(commands, resource.runtime, resource.resource_id, result, resource.guest_os);
                if (settle_ms > 0) Thread.usleep(settle_ms * 1000);
                if (FailureRules.container_exited(commands, resource.runtime, resource.resource_id))
                    return FailureRules.diagnose_container(commands, resource.runtime, resource.resource_id, null, resource.guest_os);
            } catch (Error e) {
                return ResourceIssue.from_error(e);
            }
            return null;
        }

        public ResourceIssue? stop(Resource resource) {
            string[] argv = lifecycle_argv(resource, false);
            if (argv.length == 0) return invalid_target();
            return FailureRules.check_command(commands, argv, null, 35000);
        }

        // Public for headless tests; empty when there is nothing safe to run.
        public string[] console_argv(Resource resource, out string? directory) {
            directory = null;
            if (!valid_target(resource) || resource.connect_cmd.length == 0) return {};
            directory = resource.dir.length > 0 ? resource.dir : null;
            return { "/bin/bash", "-c", resource.connect_cmd };
        }

        public ResourceIssue? open_console(Resource resource) {
            string? directory;
            string[] argv = console_argv(resource, out directory);
            if (argv.length == 0) return ResourceIssue.unsupported(_("No connect command is configured for this resource."));
            return FailureRules.check_command(commands, argv, directory);
        }

        public ResourceIssue? insert_iso(Resource resource, string iso_path) {
            return ResourceIssue.unsupported(_("Containers have no optical drive control."));
        }

        public ResourceIssue? eject_iso(Resource resource) {
            return insert_iso(resource, "");
        }

        public ResourceStatus check_status(Resource resource) {
            ResourceStatus status = ResourceStatus();
            status.ram_str = "—";
            if (!valid_target(resource)) return status;
            try {
                var inspected = commands.run({ resource.runtime.command(), "inspect", "--format", "{{.State.Running}}", resource.resource_id });
                string state = inspected.output.strip();
                if (inspected.exit_status != 0 || (state != "true" && state != "false")) return status;
                status.status_available = true;
                status.running = state == "true";
                if (!status.running) return status;
                string format = resource.runtime == ContainerRuntime.PODMAN ? "{{.CPU}}\t{{.MemUsage}}" : "{{.CPUPerc}}\t{{.MemUsage}}";
                var stats = commands.run({ resource.runtime.command(), "stats", "--no-stream", "--format", format, resource.resource_id });
                if (stats.exit_status == 0) {
                    string[] fields = stats.output.strip().split("\t");
                    if (fields.length == 2) {
                        status.cpu_pct = Metrics.container_cpu_share(fields[0], cpu_count);
                        string used = fields[1].split("/")[0].strip();
                        if (used.length > 0 && used != "--") status.ram_str = used;
                    }
                }
            } catch (Error e) {
                // Preserve authoritative running state when only statistics are inaccessible.
            }
            return status;
        }
    }
}
