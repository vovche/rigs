/* compose_driver.vala — Podman & Docker Compose container driver implementation */

namespace Rigs {

    public class ComposeDriver : Object, Driver {
        public string vm_type { get { return "compose"; } }

        public void start(VmModel vm) {
            new Thread<void*>("compose-starter", () => {
                try {
                    string? working_dir = (vm.dir.length > 0 && FileUtils.test(vm.dir, FileTest.IS_DIR)) ? vm.dir : null;
                    string cmd = (vm.start_cmd.length > 0) ? vm.start_cmd : "docker compose up -d";
                    string[] argv = { "/bin/bash", "-c", cmd };
                    Pid pid;
                    Process.spawn_async(working_dir, argv, null, SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD, null, out pid);
                    Process.close_pid(pid);
                } catch (Error e) {
                    warning("Failed to start Compose VM: %s", e.message);
                }
                return null;
            });
        }

        public void stop(VmModel vm) {
            new Thread<void*>("compose-stopper", () => {
                try {
                    string? working_dir = (vm.dir.length > 0 && FileUtils.test(vm.dir, FileTest.IS_DIR)) ? vm.dir : null;
                    string cmd = (vm.stop_cmd.length > 0) ? vm.stop_cmd : "docker compose down";
                    string[] argv = { "/bin/bash", "-c", cmd };
                    Process.spawn_sync(working_dir, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, null);
                } catch (Error e) {
                    warning("Failed to stop Compose VM: %s", e.message);
                }
                return null;
            });
        }

        public void connect_vm(VmModel vm) {
            if (vm.connect_cmd.length > 0) {
                try {
                    string? working_dir = (vm.dir.length > 0 && FileUtils.test(vm.dir, FileTest.IS_DIR)) ? vm.dir : null;
                    string[] argv = { "/bin/bash", "-c", vm.connect_cmd };
                    Pid pid;
                    Process.spawn_async(working_dir, argv, null, SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD, null, out pid);
                    Process.close_pid(pid);
                } catch (Error e) {
                    warning("Failed to connect Compose VM: %s", e.message);
                }
            }
        }

        public VmStatus check_status(VmModel vm) {
            VmStatus st = VmStatus();
            st.running = false;
            st.cpu_pct = 0.0;
            st.ram_str = "0 MB";

            if (vm.container_name.length == 0) return st;

            string stdout;
            string stderr;
            int exit_status;

            try {
                // Authoritative running state inspection
                Process.spawn_command_line_sync(
                    "podman inspect -f {{.State.Running}} " + vm.container_name,
                    out stdout, out stderr, out exit_status
                );
                if (exit_status == 0 && stdout.strip().down() == "true") {
                    st.running = true;

                    // Query container stats
                    string s_out;
                    Process.spawn_command_line_sync(
                        "podman stats --no-stream --format json " + vm.container_name,
                        out s_out, out stderr, out exit_status
                    );
                    if (exit_status == 0 && s_out.strip().length > 0) {
                        var parser = new Json.Parser();
                        parser.load_from_data(s_out);
                        var root = parser.get_root();
                        if (root != null && root.get_node_type() == Json.NodeType.ARRAY) {
                            var arr = root.get_array();
                            if (arr.get_length() > 0) {
                                var item = arr.get_object_element(0);
                                if (item.has_member("pids") && item.get_string_member("pids") != "0") {
                                    string cpu_str = item.get_string_member("cpu_percent").replace("%", "").strip();
                                    st.cpu_pct = double.parse(cpu_str);
                                    string mem_full = item.get_string_member("mem_usage");
                                    st.ram_str = mem_full.split("/")[0].strip();
                                }
                            }
                        }
                    }
                }
            } catch (Error e) {
                // Ignore
            }

            return st;
        }

        public void insert_iso(VmModel vm, string iso_path) {
            // Hot-swap/mount logic for container volumes or compose storage
        }

        public void eject_iso(VmModel vm) {
            // Eject logic for container volume mapping
        }
    }
}
