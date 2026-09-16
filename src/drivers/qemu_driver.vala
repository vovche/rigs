/* qemu_driver.vala — Standalone QEMU / KVM driver implementation */

namespace Rigs {

    // Per-VM CPU delta state for check_status
    private class CpuState : Object {
        public uint64 proc_jiffies;
        public uint64 cpu_total;
        public CpuState(uint64 p, uint64 t) { proc_jiffies = p; cpu_total = t; }
    }

    public class QemuDriver : Object, Driver {
        public string vm_type { get { return "qemu"; } }

        // Per-VM CPU delta state: vm.id → CpuState
        private HashTable<string, CpuState> cpu_prev = new HashTable<string, CpuState>(str_hash, str_equal);

        public void start(VmModel vm) {
            new Thread<void*>("qemu-starter", () => {
                try {
                    string? working_dir = (vm.dir.length > 0 && FileUtils.test(vm.dir, FileTest.IS_DIR)) ? vm.dir : null;
                    string cmd = (vm.start_cmd.length > 0) ? vm.start_cmd : "./run-vm.sh";
                    string[] argv = { "/bin/bash", "-c", cmd };
                    Process.spawn_async(working_dir, argv, null, SpawnFlags.SEARCH_PATH, null, null);
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
                        string py_cmd = "python3 -c \"import socket; s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.connect('" + vm.monitor_socket + "'); s.sendall(b'system_powerdown\\n'); s.close()\" 2>/dev/null || true";
                        string[] argv = { "/bin/bash", "-c", py_cmd };
                        Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, null);
                        Thread.usleep(1500 * 1000);
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
                    Process.spawn_async(working_dir, argv, null, SpawnFlags.SEARCH_PATH, null, null);
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
                    string[] pids = stdout.strip().split("\n");
                    foreach (string raw_pid in pids) {
                        string pid = raw_pid.strip();
                        if (pid.length == 0) continue;

                        // Check process state in /proc/[pid]/status to skip zombies
                        string proc_status;
                        try {
                            FileUtils.get_contents("/proc/" + pid + "/status", out proc_status);
                            if (proc_status.contains("State:\tZ") || proc_status.contains("State: Z")) {
                                continue;
                            }
                        } catch (Error e) {
                            continue;
                        }

                        st.running = true;

                        // --- VM CPU% via /proc/[pid]/stat delta ---
                        try {
                            // Read process CPU jiffies (utime=field14, stime=field15, sum of all threads via /proc/pid/stat)
                            string proc_stat;
                            FileUtils.get_contents("/proc/" + pid + "/stat", out proc_stat);
                            int close_paren = proc_stat.last_index_of_char(')');
                            if (close_paren > 0 && close_paren + 2 < proc_stat.length) {
                                string after_paren = proc_stat.substring(close_paren + 2);
                                string[] fields = after_paren.split(" ");
                                // fields[0] is state (field 3), fields[11] is utime (14), fields[12] is stime (15)
                                if (fields.length > 12) {
                                    uint64 utime = uint64.parse(fields[11]);
                                    uint64 stime = uint64.parse(fields[12]);
                                    uint64 proc_jiffies = utime + stime;

                                    // Read total system CPU jiffies from /proc/stat
                                    string sys_stat;
                                    uint64 cpu_total = 0;
                                    FileUtils.get_contents("/proc/stat", out sys_stat);
                                    string first_line = sys_stat.split("\n")[0];
                                    string[] cpu_fields = first_line.split(" ");
                                    for (int ci = 1; ci < cpu_fields.length; ci++) {
                                        string token = cpu_fields[ci].strip();
                                        if (token.length > 0) {
                                            cpu_total += uint64.parse(token);
                                        }
                                    }

                                    CpuState? prev = cpu_prev.lookup(vm.id);
                                    if (prev != null && cpu_total > prev.cpu_total && prev.cpu_total > 0) {
                                        uint64 delta_proc = (proc_jiffies >= prev.proc_jiffies) ? (proc_jiffies - prev.proc_jiffies) : 0;
                                        uint64 delta_total = cpu_total - prev.cpu_total;
                                        if (delta_total > 0) {
                                            st.cpu_pct = ((double)delta_proc / (double)delta_total) * 100.0;
                                            if (st.cpu_pct > 100.0) st.cpu_pct = 100.0;
                                        }
                                    }
                                    cpu_prev.insert(vm.id, new CpuState(proc_jiffies, cpu_total));
                                }
                            }
                        } catch (Error e) { }

                        // Extract VM's allocated RAM limit from cmdline (-m flag)
                        double limit_mb = 0.0;
                        try {
                            string cmdline;
                            FileUtils.get_contents("/proc/" + pid + "/cmdline", out cmdline);
                            string[] cmd_parts = cmdline.split("\0");
                            for (int ci = 0; ci < cmd_parts.length; ci++) {
                                if (cmd_parts[ci] == "-m" && ci + 1 < cmd_parts.length) {
                                    limit_mb = ConfigManager.parse_mem_to_mb(cmd_parts[ci + 1]);
                                    break;
                                }
                            }
                        } catch (Error ce) { }

                        // Fallback: check run-vm.sh in vm.dir if cmdline didn't yield -m
                        if (limit_mb <= 0.0 && vm.dir.length > 0) {
                            try {
                                string run_script;
                                string script_path = Path.build_filename(vm.dir, "run-vm.sh");
                                if (FileUtils.test(script_path, FileTest.EXISTS)) {
                                    FileUtils.get_contents(script_path, out run_script);
                                    string[] s_lines = run_script.split("\n");
                                    foreach (string sl in s_lines) {
                                        string trimmed = sl.strip();
                                        if (trimmed.has_prefix("-m ") || trimmed.has_prefix("-m\t")) {
                                            string val = trimmed.substring(3).replace("\\", "").strip();
                                            limit_mb = ConfigManager.parse_mem_to_mb(val);
                                            break;
                                        }
                                    }
                                }
                            } catch (Error se) { }
                        }

                        // --- RAM via /proc/[pid]/statm ---
                        try {
                            string statm;
                            FileUtils.get_contents("/proc/" + pid + "/statm", out statm);
                            string[] parts = statm.split(" ");
                            if (parts.length > 1) {
                                uint64 resident_pages = uint64.parse(parts[1]);
                                uint64 ram_mb = (resident_pages * 4096) / (1024 * 1024);
                                if (limit_mb > 0.0) {
                                    st.ram_pct = ((double)ram_mb / (double)limit_mb) * 100.0;
                                    if (st.ram_pct > 100.0) st.ram_pct = 100.0;
                                    st.ram_str = "%.2f GB / %.1f GB".printf((double)ram_mb / 1024.0, limit_mb / 1024.0);
                                } else {
                                    if (ram_mb > 1024) {
                                        st.ram_str = "%.2f GB".printf((double)ram_mb / 1024.0);
                                    } else {
                                        st.ram_str = "%lu MB".printf((ulong)ram_mb);
                                    }
                                    st.ram_pct = 0.0;
                                }
                            }
                        } catch (Error e) { }
                        break;
                    }
                }

                if (!st.running) {
                    // Clear stale CPU delta state when VM is not running
                    cpu_prev.remove(vm.id);
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
