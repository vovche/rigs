/* compose_driver.vala — Explicitly configured compose projects. */
namespace Rigs {
    public class ComposeDriver : Object, Driver {
        public string vm_type { get { return "compose"; } }

        private void lifecycle(VmModel vm, bool starting) {
            new Thread<void*>("compose-lifecycle", () => {
                try {
                    if (vm.runtime != "podman" && vm.runtime != "docker") return null;
                    string cmd = starting ? vm.start_cmd : vm.stop_cmd;
                    var host = new HostCommand();
                    string? directory = vm.dir.length > 0 ? vm.dir : null;
                    if (cmd.length > 0) {
                        string[] argv = { "/bin/bash", "-c", cmd };
                        if (starting) host.launch(argv, directory);
                        else host.run(argv, directory, 120000);
                    } else {
                        string[] argv = { vm.runtime, "compose", starting ? "up" : "down" };
                        if (starting) { argv += "-d"; host.launch(argv, directory); }
                        else host.run(argv, directory, 120000);
                    }
                } catch (Error e) { warning("Compose command failed: %s", e.message); }
                return null;
            });
        }

        public void start(VmModel vm) { lifecycle(vm, true); }
        public void stop(VmModel vm) { lifecycle(vm, false); }

        public void connect_vm(VmModel vm) {
            if (vm.connect_cmd.length == 0) return;
            try {
                new HostCommand().launch({"/bin/bash", "-c", vm.connect_cmd}, vm.dir.length > 0 ? vm.dir : null);
            } catch (Error e) { warning("Failed to connect: %s", e.message); }
        }

        public VmStatus check_status(VmModel vm) {
            VmStatus st = VmStatus();
            st.ram_str = "0 MB";
            if (vm.container_name.length == 0 || vm.container_name.has_prefix("-") ||
                (vm.runtime != "podman" && vm.runtime != "docker")) return st;
            try {
                var host = new HostCommand();
                var result = host.run({vm.runtime, "inspect", "--format", "{{.State.Running}}", vm.container_name});
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
                    string template = vm.runtime == "podman" ? "{{.CPU}}\t{{.MemUsage}}" : "{{.CPUPerc}}\t{{.MemUsage}}";
                    result = host.run({vm.runtime, "stats", "--no-stream", "--format", template, vm.container_name});
                    if (result.exit_status == 0) {
                        var parts = result.output.strip().split("\t");
                        if (parts.length == 2) {
                            st.cpu_pct = double.parse(parts[0].replace("%", "")).clamp(0, 100);
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

        public void insert_iso(VmModel vm, string iso_path) { }
        public void eject_iso(VmModel vm) { }
    }
}
