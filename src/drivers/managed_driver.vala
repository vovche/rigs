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
                if (kind == "container") {
                    if (settle_ms > 0) Thread.usleep(settle_ms * 1000);
                    if (StartupDiagnostics.exited_after_start(commands, vm.runtime, container))
                        return StartupDiagnostics.diagnose(commands, vm.runtime, container, null, vm.guest_os);
                }
            } catch (Error e) {
                warning("Managed resource operation failed: %s", e.message);
            }
            return null;
        }

        private void change_state(VmModel vm, bool starting) {
            string[] argv = lifecycle_argv(vm, starting);
            if (argv.length == 0) return;
            new Thread<void*>("managed-lifecycle", () => {
                if (starting) {
                    var issue = start_blocking(vm);
                    if (issue != null) StartupDiagnostics.publish(vm, issue);
                    return null;
                }
                try {
                    var result = commands.run(argv, null, 35000);
                    if (result.exit_status != 0)
                        warning("Managed resource operation failed: %s", result.error_output);
                } catch (Error e) {
                    warning("Managed resource operation failed: %s", e.message);
                }
                return null;
            });
        }

        public void start(VmModel vm) { change_state(vm, true); }
        public void stop(VmModel vm) { change_state(vm, false); }

        public void connect_vm(VmModel vm) {
            if (!valid_target(vm)) return;
            try {
                if (kind == "libvirt") {
                    commands.launch({ "virt-viewer", "--connect", vm.connection_uri, vm.resource_id });
                } else if (vm.connect_cmd.length > 0) {
                    commands.launch({ "/bin/bash", "-c", vm.connect_cmd },
                        vm.dir.length > 0 ? vm.dir : null);
                }
            } catch (Error e) {
                warning("Could not open resource viewer: %s", e.message);
            }
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
                            double cpu;
                            if (double.try_parse(fields[0].replace("%", "").strip(), out cpu) && cpu >= 0 && cpu < double.MAX)
                                status.cpu_pct = cpu;
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
