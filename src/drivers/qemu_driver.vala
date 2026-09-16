/* qemu_driver.vala — Standalone QEMU / KVM driver implementation */

namespace Rigs {

    public class QemuDriver : Object, Driver {
        public string vm_type { get { return "qemu"; } }

        public void start(VmModel vm) {
            new Thread<void*>("qemu-starter", () => {
                try {
                    string? working_dir = (vm.dir.length > 0 && FileUtils.test(vm.dir, FileTest.IS_DIR)) ? vm.dir : null;
                    string cmd = (vm.start_cmd.length > 0) ? vm.start_cmd : "./run-vm.sh";
                    string[] argv = { "/bin/bash", "-c", cmd };
                    Pid pid;
                    Process.spawn_async(working_dir, argv, null, SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD, null, out pid);
                    Process.close_pid(pid);
                } catch (Error e) {
                    warning("Failed to start QEMU VM: %s", e.message);
                }
                return null;
            });
        }

        public void stop(VmModel vm) {
            new Thread<void*>("qemu-stopper", () => {
                try {
                    if (vm.monitor_socket.length > 0 && FileUtils.test(vm.monitor_socket, FileTest.EXISTS)) {
                        string[] argv = { "/bin/bash", "-c", "echo system_powerdown | socat - UNIX-CONNECT:" + vm.monitor_socket };
                        Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, null);
                        Thread.usleep(1000 * 1000);
                    }
                    if (vm.process_name.length > 0) {
                        string[] argv = { "/bin/bash", "-c", "pkill -f " + vm.process_name };
                        Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, null);
                    }
                } catch (Error e) {
                    warning("Failed to stop QEMU VM: %s", e.message);
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
                    warning("Failed to connect QEMU VM: %s", e.message);
                }
            }
        }

        public VmStatus check_status(VmModel vm) {
            VmStatus st = VmStatus();
            st.running = false;
            st.cpu_pct = 0.0;
            st.ram_str = "0 MB";

            if (vm.process_name.length == 0) return st;

            try {
                string stdout;
                string stderr;
                int exit_status;
                Process.spawn_command_line_sync(
                    "pgrep -f " + vm.process_name,
                    out stdout, out stderr, out exit_status
                );
                if (exit_status == 0 && stdout.strip().length > 0) {
                    st.running = true;
                    string pid = stdout.strip().split("\n")[0].strip();

                    // Query /proc/[pid]/statm for RSS memory (resident pages * 4096)
                    string statm;
                    FileUtils.get_contents("/proc/" + pid + "/statm", out statm);
                    string[] parts = statm.split(" ");
                    if (parts.length > 1) {
                        uint64 resident_pages = uint64.parse(parts[1]);
                        uint64 ram_mb = (resident_pages * 4096) / (1024 * 1024);
                        if (ram_mb > 1024) {
                            st.ram_str = "%.2f GB".printf((double)ram_mb / 1024.0);
                        } else {
                            st.ram_str = "%llu MB".printf(ram_mb);
                        }
                    }
                }
            } catch (Error e) {
                // Ignore
            }

            return st;
        }

        public void insert_iso(VmModel vm, string iso_path) {
            if (vm.monitor_socket.length > 0 && FileUtils.test(vm.monitor_socket, FileTest.EXISTS)) {
                new Thread<void*>("qemu-iso-insert", () => {
                    try {
                        string cmd = "echo 'change cdrom " + iso_path + "' | socat - UNIX-CONNECT:" + vm.monitor_socket;
                        string[] argv = { "/bin/bash", "-c", cmd };
                        Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, null);
                    } catch (Error e) {
                        warning("Failed to hot-insert ISO: %s", e.message);
                    }
                    return null;
                });
            }
        }

        public void eject_iso(VmModel vm) {
            if (vm.monitor_socket.length > 0 && FileUtils.test(vm.monitor_socket, FileTest.EXISTS)) {
                new Thread<void*>("qemu-iso-eject", () => {
                    try {
                        string cmd = "echo 'eject -f cdrom' | socat - UNIX-CONNECT:" + vm.monitor_socket;
                        string[] argv = { "/bin/bash", "-c", cmd };
                        Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, null);
                    } catch (Error e) {
                        warning("Failed to hot-eject ISO: %s", e.message);
                    }
                    return null;
                });
            }
        }
    }
}
