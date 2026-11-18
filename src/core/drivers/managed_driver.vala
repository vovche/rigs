/* Managed resources use stable runtime identities, never generated shell commands. */
namespace Rigs {
    public class ManagedDriver : Object, Driver {
        private string managed_kind;
        private HostCommand commands;

        public string kind { get { return managed_kind; } }

        public ManagedDriver(string managed_kind, HostCommand? commands = null) {
            this.managed_kind = managed_kind;
            this.commands = commands ?? new HostCommand();
        }

        private bool valid_target(Resource resource) {
            if (managed_kind == "container") {
                return (resource.runtime == "podman" || resource.runtime == "docker") &&
                    Regex.match_simple("^[a-fA-F0-9]{12,64}$", resource.resource_id);
            }
            return managed_kind == "libvirt" &&
                (resource.connection_uri == "qemu:///session" || resource.connection_uri == "qemu:///system") &&
                Regex.match_simple("^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$", resource.resource_id);
        }

        // Public for deterministic lifecycle contract tests without starting real resources.
        public string[] lifecycle_argv(Resource resource, bool starting) {
            if (!valid_target(resource)) return {};
            if (managed_kind == "container") {
                if (starting) return { resource.runtime, "start", resource.resource_id };
                return { resource.runtime, "stop", "--time", "30", resource.resource_id };
            }
            return { "virsh", "--connect", resource.connection_uri,
                starting ? "start" : "shutdown", resource.resource_id };
        }

        // Milliseconds to wait before checking whether a started container exited at once.
        public uint settle_ms = 2000;
        // 0 = host CPU count; tests pin it for deterministic percentages.
        public uint cpu_count = 0;

        // Synchronous start; returns the diagnosed failure, if any. Public for headless tests.
        public ResourceIssue? start_blocking(Resource resource) {
            string[] argv = lifecycle_argv(resource, true);
            if (argv.length == 0) return null;
            string container = managed_kind == "container" ? resource.resource_id : "";
            try {
                var result = commands.run(argv, null, 30000);
                if (result.exit_status != 0) {
                    return FailureRules.diagnose(commands, resource.runtime, container, result, resource.guest_os);
                }
                if (settle_ms > 0) Thread.usleep(settle_ms * 1000);
                if (managed_kind == "container") {
                    if (FailureRules.exited_after_start(commands, resource.runtime, container))
                        return FailureRules.diagnose(commands, resource.runtime, container, null, resource.guest_os);
                } else {
                    return libvirt_exited_after_start(resource);
                }
            } catch (Error e) {
                return FailureRules.from_error(e);
            }
            return null;
        }

        // `virsh start` succeeds before QEMU has fully come up; a domain that died at once is "shut off"/"crashed".
        private ResourceIssue? libvirt_exited_after_start(Resource resource) throws Error {
            var state = commands.run({ "virsh", "--connect", resource.connection_uri, "domstate", "--reason", resource.resource_id });
            string text = state.output.strip();
            if (state.exit_status != 0 || !(text.has_prefix("shut off") || text.has_prefix("crashed"))) return null;
            return FailureRules.not_running(text,
                "virsh --connect %s dominfo %s".printf(resource.connection_uri, resource.resource_id));
        }

        public void start(Resource resource) {
            if (lifecycle_argv(resource, true).length == 0) return;
            FailureRules.run_in_background(resource, "managed-start", () => start_blocking(resource));
        }

        public void stop(Resource resource) {
            string[] argv = lifecycle_argv(resource, false);
            if (argv.length == 0) return;
            FailureRules.run_in_background(resource, "managed-stop", () =>
                FailureRules.check_command(commands, argv, null, ResourceOperation.STOP, 35000));
        }

        // Public for headless tests; empty when there is nothing safe to run.
        public string[] connect_argv(Resource resource, out string? directory) {
            directory = null;
            if (!valid_target(resource)) return {};
            if (managed_kind == "libvirt") return { "virt-viewer", "--connect", resource.connection_uri, resource.resource_id };
            if (resource.connect_cmd.length == 0) return {};
            directory = resource.dir.length > 0 ? resource.dir : null;
            return { "/bin/bash", "-c", resource.connect_cmd };
        }

        public void open_console(Resource resource) {
            string? directory;
            string[] argv = connect_argv(resource, out directory);
            if (argv.length == 0) return;
            FailureRules.run_in_background(resource, "managed-connect", () =>
                FailureRules.check_command(commands, argv, directory, ResourceOperation.CONNECT));
        }

        public ResourceStatus check_status(Resource resource) {
            ResourceStatus status = ResourceStatus();
            status.ram_str = "—";
            if (!valid_target(resource)) return status;
            try {
                if (managed_kind == "container") {
                    var inspected = commands.run({ resource.runtime, "inspect", "--format", "{{.State.Running}}", resource.resource_id });
                    string state = inspected.output.strip();
                    if (inspected.exit_status != 0 || (state != "true" && state != "false")) return status;
                    status.status_available = true;
                    status.running = state == "true";
                    if (!status.running) return status;
                    string format = resource.runtime == "podman" ? "{{.CPU}}\t{{.MemUsage}}" : "{{.CPUPerc}}\t{{.MemUsage}}";
                    var stats = commands.run({ resource.runtime, "stats", "--no-stream", "--format", format, resource.resource_id });
                    if (stats.exit_status == 0) {
                        string[] fields = stats.output.strip().split("\t");
                        if (fields.length == 2) {
                            status.cpu_pct = Metrics.container_cpu_share(fields[0], cpu_count);
                            string used = fields[1].split("/")[0].strip();
                            if (used.length > 0 && used != "--") status.ram_str = used;
                        }
                    }
                } else {
                    // HostCommand supplies LC_ALL=C so virsh field names are stable.
                    var info = commands.run({ "virsh", "--connect", resource.connection_uri, "dominfo", resource.resource_id });
                    if (info.exit_status != 0) return status;
                    string state = "";
                    string memory = "";
                    foreach (string line in info.output.split("\n")) {
                        int colon = line.index_of(":");
                        if (colon < 0) continue;
                        string key = line.substring(0, colon).strip();
                        string value = line.substring(colon + 1).strip();
                        if (key == "State") state = value;
                        if (key == "Used memory") memory = value;
                    }
                    switch (state) {
                        case "running": case "paused": case "idle": case "in shutdown": case "pmsuspended":
                            status.running = true;
                            break;
                        case "shut off": case "crashed":
                            break;
                        default:
                            return status;
                    }
                    status.status_available = true;
                    if (memory.length > 0) status.ram_str = memory;
                }
            } catch (Error e) {
                // Preserve authoritative running state when only statistics are inaccessible.
            }
            return status;
        }

        public void insert_iso(Resource resource, string iso_path) { }
        public void eject_iso(Resource resource) { }
    }
}
