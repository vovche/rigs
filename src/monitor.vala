/* monitor.vala — Background resource and status monitor for Rigs */

namespace Rigs {

    public class SystemMonitor : Object {
        private bool active = false;
        private Thread<void*>? worker_thread = null;

        // Previous CPU counters for delta calculation
        private uint64 prev_idle = 0;
        private uint64 prev_total = 0;

        public signal void updated(HostStatus host, HashTable<string, VmStatus?> vm_statuses);

        public void start(GenericArray<VmModel> vms) {
            active = true;
            worker_thread = new Thread<void*>("rigs-monitor", () => {
                while (active) {
                    HostStatus host = read_host_status();
                    var results = new HashTable<string, VmStatus?>(str_hash, str_equal);

                    for (int i = 0; i < vms.length; i++) {
                        VmModel vm = vms[i];
                        VmStatus st = check_vm(vm);
                        results.insert(vm.id, st);
                    }

                    Idle.add(() => {
                        if (active) {
                            updated(host, results);
                        }
                        return Source.REMOVE;
                    });

                    Thread.usleep(1500 * 1000); // 1.5 seconds
                }
                return null;
            });
        }

        public void stop() {
            active = false;
        }

        private HostStatus read_host_status() {
            HostStatus status = HostStatus();

            // 1. CPU via /proc/stat
            try {
                string stat_content;
                FileUtils.get_contents("/proc/stat", out stat_content);
                string[] lines = stat_content.split("\n");
                if (lines.length > 0 && lines[0].has_prefix("cpu ")) {
                    string[] tokens = lines[0].split(" ");
                    // tokens: "cpu", "", user, nice, system, idle, iowait, irq, softirq, steal
                    uint64 user = 0, nice = 0, sys = 0, idle = 0, iowait = 0, irq = 0, softirq = 0, steal = 0;
                    int count = 0;
                    for (int i = 1; i < tokens.length; i++) {
                        if (tokens[i].length == 0) continue;
                        uint64 val = uint64.parse(tokens[i]);
                        switch (count) {
                            case 0: user = val; break;
                            case 1: nice = val; break;
                            case 2: sys = val; break;
                            case 3: idle = val; break;
                            case 4: iowait = val; break;
                            case 5: irq = val; break;
                            case 6: softirq = val; break;
                            case 7: steal = val; break;
                        }
                        count++;
                    }

                    uint64 total_idle = idle + iowait;
                    uint64 total_non_idle = user + nice + sys + irq + softirq + steal;
                    uint64 total = total_idle + total_non_idle;

                    if (prev_total > 0 && total > prev_total) {
                        uint64 delta_total = total - prev_total;
                        uint64 delta_idle = total_idle - prev_idle;
                        status.cpu_pct = ((double)(delta_total - delta_idle) / (double)delta_total) * 100.0;
                    }

                    prev_idle = total_idle;
                    prev_total = total;
                }
            } catch (Error e) {
                // Ignore proc errors
            }

            // 2. RAM via /proc/meminfo
            try {
                string mem_content;
                FileUtils.get_contents("/proc/meminfo", out mem_content);
                uint64 total_kb = 0;
                uint64 avail_kb = 0;

                string[] lines = mem_content.split("\n");
                foreach (unowned string line in lines) {
                    if (line.has_prefix("MemTotal:")) {
                        total_kb = parse_meminfo_val(line);
                    } else if (line.has_prefix("MemAvailable:")) {
                        avail_kb = parse_meminfo_val(line);
                    }
                }

                if (total_kb > 0) {
                    uint64 used_kb = total_kb - avail_kb;
                    status.ram_total_gb = (double)total_kb / (1024.0 * 1024.0);
                    status.ram_used_gb = (double)used_kb / (1024.0 * 1024.0);
                    status.ram_pct = ((double)used_kb / (double)total_kb) * 100.0;
                }
            } catch (Error e) {
                // Ignore
            }

            return status;
        }

        private uint64 parse_meminfo_val(string line) {
            string[] parts = line.split(":");
            if (parts.length > 1) {
                string val_str = parts[1].strip().split(" ")[0].strip();
                return uint64.parse(val_str);
            }
            return 0;
        }

        private VmStatus check_vm(VmModel vm) {
            VmStatus st = VmStatus();
            st.running = false;
            st.cpu_pct = 0.0;
            st.ram_str = "0 MB";

            if (vm.vm_type == "compose") {
                if (vm.container_name.length == 0) return st;

                // podman inspect -f '{{.State.Running}}'
                string stdout;
                string stderr;
                int exit_status;
                try {
                    Process.spawn_command_line_sync(
                        "podman inspect -f {{.State.Running}} " + vm.container_name,
                        out stdout, out stderr, out exit_status
                    );
                    if (exit_status == 0 && stdout.strip().down() == "true") {
                        st.running = true;

                        // Get stats
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
            } else if (vm.vm_type == "qemu") {
                if (vm.process_name.length == 0) return st;

                try {
                    string stdout;
                    string stderr;
                    int exit_status;
                    // Check if qemu process is running
                    Process.spawn_command_line_sync(
                        "pgrep -f " + vm.process_name,
                        out stdout, out stderr, out exit_status
                    );
                    if (exit_status == 0 && stdout.strip().length > 0) {
                        st.running = true;
                        string pid = stdout.strip().split("\n")[0].strip();

                        // Read /proc/[pid]/statm for RSS memory (pages * 4KB)
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
            }

            return st;
        }
    }
}
