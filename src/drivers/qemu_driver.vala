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

        // Overridable for headless tests with a fake procfs tree.
        public string proc_root = "/proc";

        private static uint64 page_size() {
            long size = Posix.sysconf(Posix._SC_PAGESIZE);
            return size > 0 ? (uint64) size : 4096;
        }

        // Native replacement for `pgrep -f`: substring match on the full command line,
        // skipping ourselves, kernel threads and zombies. Several matches (wrapper
        // scripts, editors, tail -f) resolve to the largest resident set: the VM itself.
        public static int find_vm_pid(string proc_root, string pattern, int self_pid) {
            if (pattern.strip().length == 0) return -1;
            int best = -1;
            uint64 best_rss = 0;
            try {
                var dir = Dir.open(proc_root);
                string? name;
                while ((name = dir.read_name()) != null) {
                    int pid;
                    if (!int.try_parse(name, out pid) || pid <= 0 || pid == self_pid) continue;
                    string base_path = Path.build_filename(proc_root, name);
                    try {
                        uint8[] raw;
                        FileUtils.get_data(Path.build_filename(base_path, "cmdline"), out raw);
                        if (raw.length == 0) continue;
                        for (int i = 0; i < raw.length; i++) if (raw[i] == 0) raw[i] = ' ';
                        string cmdline = HostCommand.bytes_to_text(new Bytes(raw));
                        if (!cmdline.contains(pattern)) continue;
                        string status;
                        FileUtils.get_contents(Path.build_filename(base_path, "status"), out status);
                        if (Regex.match_simple("^State:\\s*Z", status, RegexCompileFlags.MULTILINE)) continue;
                        string statm;
                        FileUtils.get_contents(Path.build_filename(base_path, "statm"), out statm);
                        string[] parts = statm.strip().split(" ");
                        uint64 rss = parts.length > 1 ? uint64.parse(parts[1]) : 0;
                        if (best < 0 || rss > best_rss) { best = pid; best_rss = rss; }
                    } catch (Error e) {
                        continue; // Processes exit while we scan.
                    }
                }
            } catch (Error e) { }
            return best;
        }

        public void start(VmModel vm) {
            new Thread<void*>("qemu-starter", () => {
                try {
                    string? working_dir = vm.dir.length > 0 ? vm.dir : null;
                    string cmd = (vm.start_cmd.length > 0) ? vm.start_cmd : "./run-vm.sh";
                    string[] argv = { "/bin/bash", "-c", cmd };
                    new HostCommand().launch(argv, working_dir);
                } catch (Error e) {
                    warning("Failed to start QEMU VM: %s", e.message);
                }
                return null;
            });
        }

        public void stop(VmModel vm) {
            new Thread<void*>("qemu-stopper", () => {
                try {
                    var host = new HostCommand();
                    string? directory = vm.dir.length > 0 ? vm.dir : null;
                    if (vm.stop_cmd.length > 0) {
                        host.run({"/bin/bash", "-c", vm.stop_cmd}, directory, 120000);
                    } else if (vm.monitor_socket.length > 0) {
                        HmpMonitor.send(vm.monitor_socket, "system_powerdown");
                    }
                } catch (Error e) { warning("Failed to stop QEMU VM: %s", e.message); }
                return null;
            });
        }

        public void connect_vm(VmModel vm) {
            if (vm.connect_cmd.length > 0) {
                try {
                    string? working_dir = vm.dir.length > 0 ? vm.dir : null;
                    string[] argv = { "/bin/bash", "-c", vm.connect_cmd };
                    new HostCommand().launch(argv, working_dir);
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

            // Direct process monitoring requires the host procfs. Sandboxed
            // deployments should use libvirt's stable domain interface.
            string mode = new HostCommand().mode;
            if (mode != "native" && mode != "snap-classic") return st;
            st.status_available = true;
            if (vm.process_name.length == 0) return st;

            int pid = find_vm_pid(proc_root, vm.process_name, (int) Posix.getpid());
            if (pid <= 0) {
                cpu_prev.remove(vm.id);
                return st;
            }
            st.running = true;
            string pid_dir = Path.build_filename(proc_root, pid.to_string());
            st.cpu_pct = process_cpu_percent(vm.id, pid_dir);
            double limit_mb = allocated_mb(pid_dir, vm.dir);
            uint64 ram_mb = resident_mb(pid_dir);
            if (limit_mb > 0.0) {
                st.ram_pct = double.min(100.0, ram_mb / limit_mb * 100.0);
                st.ram_str = "%.2f GB / %.1f GB".printf(ram_mb / 1024.0, limit_mb / 1024.0);
            } else {
                st.ram_str = ram_mb > 1024 ? "%.2f GB".printf(ram_mb / 1024.0) : "%lu MB".printf((ulong) ram_mb);
            }
            return st;
        }

        // Share of the whole host (all CPUs), matching the host overview and container drivers.
        private double process_cpu_percent(string vm_id, string pid_dir) {
            try {
                string proc_stat;
                FileUtils.get_contents(Path.build_filename(pid_dir, "stat"), out proc_stat);
                int close_paren = proc_stat.last_index_of_char(')');
                if (close_paren <= 0 || close_paren + 2 >= proc_stat.length) return 0.0;
                // After ")": fields[0] is state (field 3), [11] utime (14), [12] stime (15).
                string[] fields = proc_stat.substring(close_paren + 2).split(" ");
                if (fields.length <= 12) return 0.0;
                uint64 proc_jiffies = uint64.parse(fields[11]) + uint64.parse(fields[12]);

                string sys_stat;
                FileUtils.get_contents(Path.build_filename(proc_root, "stat"), out sys_stat);
                uint64 cpu_total = 0;
                // Keep the split result in a local: slicing a temporary array is a use-after-free in Vala.
                string[] cpu_fields = sys_stat.split("\n")[0].split(" ");
                for (int i = 1; i < cpu_fields.length; i++) {
                    if (cpu_fields[i].strip().length > 0) cpu_total += uint64.parse(cpu_fields[i].strip());
                }

                CpuState? prev = cpu_prev.lookup(vm_id);
                cpu_prev.insert(vm_id, new CpuState(proc_jiffies, cpu_total));
                if (prev == null) return 0.0;
                return Metrics.delta_percent(prev.proc_jiffies, proc_jiffies, prev.cpu_total, cpu_total);
            } catch (Error e) {
                return 0.0;
            }
        }

        // VM RAM limit from the QEMU "-m" argument, else from run-vm.sh in the VM directory.
        private static double allocated_mb(string pid_dir, string vm_dir) {
            try {
                uint8[] raw;
                FileUtils.get_data(Path.build_filename(pid_dir, "cmdline"), out raw);
                string[] args = {};
                int start = 0;
                for (int i = 0; i < raw.length; i++) {
                    if (raw[i] != 0) continue;
                    args += HostCommand.bytes_to_text(new Bytes(raw[start:i]));
                    start = i + 1;
                }
                for (int i = 0; i + 1 < args.length; i++) {
                    if (args[i] == "-m") return ConfigManager.parse_mem_to_mb(args[i + 1]);
                }
            } catch (Error e) { }
            if (vm_dir.length == 0) return 0.0;
            try {
                string script;
                FileUtils.get_contents(Path.build_filename(vm_dir, "run-vm.sh"), out script);
                foreach (string line in script.split("\n")) {
                    string trimmed = line.strip();
                    if (trimmed.has_prefix("-m ") || trimmed.has_prefix("-m\t"))
                        return ConfigManager.parse_mem_to_mb(trimmed.substring(3).replace("\\", "").strip());
                }
            } catch (Error e) { }
            return 0.0;
        }

        private static uint64 resident_mb(string pid_dir) {
            try {
                string statm;
                FileUtils.get_contents(Path.build_filename(pid_dir, "statm"), out statm);
                string[] parts = statm.strip().split(" ");
                if (parts.length > 1) return uint64.parse(parts[1]) * page_size() / (1024 * 1024);
            } catch (Error e) { }
            return 0;
        }

        public void insert_iso(VmModel vm, string iso_path) {
            if (vm.monitor_socket.length == 0) return;
            string command;
            try {
                command = "change cdrom " + HmpMonitor.quote(iso_path);
            } catch (Error e) {
                warning("Refusing ISO path: %s", e.message);
                return;
            }
            send_async(vm.monitor_socket, command);
        }

        public void eject_iso(VmModel vm) {
            if (vm.monitor_socket.length > 0) send_async(vm.monitor_socket, "eject -f cdrom");
        }

        private static void send_async(string socket_path, string command) {
            new Thread<void*>("qemu-hmp", () => {
                try { HmpMonitor.send(socket_path, command); }
                catch (Error e) { warning("QEMU monitor command failed: %s", e.message); }
                return null;
            });
        }
    }
}
