/* Managed resources use stable runtime identities, never generated shell commands. */
namespace Rigs {
    public class ManagedDriver : Object, Driver {
        private string kind;
        private HostCommand commands;

        public string vm_type { get { return kind; } }

        public ManagedDriver(string kind, HostCommand? commands = null) {
            this.kind = kind;
            this.commands = commands ?? new HostCommand();
        }

        private bool valid_target(VmModel vm) {
            if (kind == "container") {
                return (vm.runtime == "podman" || vm.runtime == "docker") &&
                    Regex.match_simple("^[a-fA-F0-9]{12,64}$", vm.resource_id);
            }
            return kind == "libvirt" &&
                (vm.connection_uri == "qemu:///session" || vm.connection_uri == "qemu:///system") &&
                Regex.match_simple("^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$", vm.resource_id);
        }

        // Public for deterministic lifecycle contract tests without starting real resources.
        public string[] lifecycle_argv(VmModel vm, bool starting) {
            if (!valid_target(vm)) return {};
            if (kind == "container") {
                if (starting) return { vm.runtime, "start", vm.resource_id };
                return { vm.runtime, "stop", "--time", "30", vm.resource_id };
            }
            return { "virsh", "--connect", vm.connection_uri,
                starting ? "start" : "shutdown", vm.resource_id };
        }

        // Milliseconds to wait before checking whether a started container exited at once.
        public uint settle_ms = 2000;
        // 0 = host CPU count; tests pin it for deterministic percentages.
        public uint cpu_count = 0;

        // Synchronous start; returns the diagnosed failure, if any. Public for headless tests.
        public StartupIssue? start_blocking(VmModel vm) {
            string[] argv = lifecycle_argv(vm, true);
            if (argv.length == 0) return null;
            string container = kind == "container" ? vm.resource_id : "";
            try {
                var result = commands.run(argv, null, 30000);
                if (result.exit_status != 0) {
                    return StartupDiagnostics.diagnose(commands, vm.runtime, container, result, vm.guest_os);
                }
                if (settle_ms > 0) Thread.usleep(settle_ms * 1000);
                if (kind == "container") {
                    if (StartupDiagnostics.exited_after_start(commands, vm.runtime, container))
                        return StartupDiagnostics.diagnose(commands, vm.runtime, container, null, vm.guest_os);
                } else {
                    return libvirt_exited_after_start(vm);
                }
            } catch (Error e) {
                return StartupDiagnostics.from_error(e);
            }
            return null;
        }

        // `virsh start` succeeds before QEMU has fully come up; a domain that died at once is "shut off"/"crashed".
        private StartupIssue? libvirt_exited_after_start(VmModel vm) throws Error {
            var state = commands.run({ "virsh", "--connect", vm.connection_uri, "domstate", "--reason", vm.resource_id });
            string text = state.output.strip();
            if (state.exit_status != 0 || !(text.has_prefix("shut off") || text.has_prefix("crashed"))) return null;
            return StartupDiagnostics.not_running(text,
                "virsh --connect %s dominfo %s".printf(vm.connection_uri, vm.resource_id));
        }

        public void start(VmModel vm) {
            if (lifecycle_argv(vm, true).length == 0) return;
            StartupDiagnostics.run_in_background(vm, "managed-start", () => start_blocking(vm));
        }

        public void stop(VmModel vm) {
            string[] argv = lifecycle_argv(vm, false);
            if (argv.length == 0) return;
            StartupDiagnostics.run_in_background(vm, "managed-stop", () =>
                StartupDiagnostics.check_command(commands, argv, null, ResourceOperation.STOP, 35000));
        }

        // Public for headless tests; empty when there is nothing safe to run.
        public string[] connect_argv(VmModel vm, out string? directory) {
            directory = null;
            if (!valid_target(vm)) return {};
            if (kind == "libvirt") return { "virt-viewer", "--connect", vm.connection_uri, vm.resource_id };
            if (vm.connect_cmd.length == 0) return {};
            directory = vm.dir.length > 0 ? vm.dir : null;
            return { "/bin/bash", "-c", vm.connect_cmd };
        }

        public void connect_vm(VmModel vm) {
            string? directory;
            string[] argv = connect_argv(vm, out directory);
            if (argv.length == 0) return;
            StartupDiagnostics.run_in_background(vm, "managed-connect", () =>
                StartupDiagnostics.check_command(commands, argv, directory, ResourceOperation.CONNECT));
        }

        public VmStatus check_status(VmModel vm) {
            VmStatus status = VmStatus();
            status.ram_str = "—";
            if (!valid_target(vm)) return status;
            try {
                if (kind == "container") {
                    var inspected = commands.run({ vm.runtime, "inspect", "--format", "{{.State.Running}}", vm.resource_id });
                    string state = inspected.output.strip();
                    if (inspected.exit_status != 0 || (state != "true" && state != "false")) return status;
                    status.status_available = true;
                    status.running = state == "true";
                    if (!status.running) return status;
                    string format = vm.runtime == "podman" ? "{{.CPU}}\t{{.MemUsage}}" : "{{.CPUPerc}}\t{{.MemUsage}}";
                    var stats = commands.run({ vm.runtime, "stats", "--no-stream", "--format", format, vm.resource_id });
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
                    var info = commands.run({ "virsh", "--connect", vm.connection_uri, "dominfo", vm.resource_id });
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

        public void insert_iso(VmModel vm, string iso_path) { }
        public void eject_iso(VmModel vm) { }
    }
}
