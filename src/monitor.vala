/* monitor.vala — Background resource and status monitor for Rigs */

namespace Rigs {

    public enum MonitorInterval {
        FOCUSED    = 1000,  // 1 s — window has focus
        BACKGROUND = 3000,  // 3 s — visible but not focused
        SUSPENDED  = 0      // 0   — minimized/hidden: do not poll
    }

    public class SystemMonitor : Object {
        // Read by the worker thread: always access through AtomicInt.
        private int active = 0;
        private Thread<void*>? worker_thread = null;
        private MonitorInterval interval = MonitorInterval.BACKGROUND;
        private Mutex mutex = Mutex();
        private Cond cond = Cond();
        private GenericArray<VmModel> monitored_vms = new GenericArray<VmModel>();

        // Previous CPU counters for delta calculation
        private uint64 prev_idle = 0;
        private uint64 prev_total = 0;

        public signal void updated(HostStatus host, HashTable<string, VmStatus?> vm_statuses);

        public void set_interval(MonitorInterval new_interval) {
            mutex.lock();
            interval = new_interval;
            cond.signal();
            mutex.unlock();
        }

        public void start(GenericArray<VmModel> vms) {
            set_vms(vms);
            AtomicInt.set(ref active, 1);
            worker_thread = new Thread<void*>("rigs-monitor", () => {
                while (AtomicInt.get(ref active) == 1) {
                    mutex.lock();
                    while (AtomicInt.get(ref active) == 1 && interval == MonitorInterval.SUSPENDED) {
                        cond.wait(mutex);
                    }
                    if (AtomicInt.get(ref active) == 0) {
                        mutex.unlock();
                        break;
                    }
                    uint32 sleep_ms = (uint32)interval;
                    var snapshot = monitored_vms;
                    mutex.unlock();

                    HostStatus host = read_host_status();
                    var results = new HashTable<string, VmStatus?>(str_hash, str_equal);

                    for (int i = 0; i < snapshot.length; i++) {
                        VmModel vm = snapshot[i];
                        VmStatus st = check_vm(vm);
                        results.insert(vm.id, st);
                    }

                    Idle.add(() => {
                        if (AtomicInt.get(ref active) == 1) {
                            updated(host, results);
                        }
                        return Source.REMOVE;
                    });

                    mutex.lock();
                    if (AtomicInt.get(ref active) == 1) {
                        int64 end_time = get_monotonic_time() + ((int64)sleep_ms * 1000);
                        cond.wait_until(mutex, end_time);
                    }
                    mutex.unlock();
                }
                return null;
            });
        }

        // Called by the GTK thread after registration/removal/settings changes.
        // The worker never traverses the mutable UI array or mutable VM models.
        public void set_vms(GenericArray<VmModel> vms) {
            var snapshot = new GenericArray<VmModel>();
            for (int i = 0; i < vms.length; i++) {
                var node = new Json.Node(Json.NodeType.OBJECT);
                node.set_object(vms[i].to_json_object());
                snapshot.add(VmModel.from_json_node(node));
            }
            mutex.lock();
            monitored_vms = snapshot;
            cond.signal();
            mutex.unlock();
        }

        public void stop() {
            mutex.lock();
            AtomicInt.set(ref active, 0);
            cond.signal();
            mutex.unlock();
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

                    if (prev_total > 0) status.cpu_pct = Metrics.busy_percent(prev_idle, prev_total, total_idle, total);

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
                    uint64 used_kb = Metrics.saturating_delta(avail_kb, total_kb);
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
            Driver? driver = DriverRegistry.get_default().get_driver(vm.vm_type);
            if (driver != null) {
                var status = driver.check_status(vm);
                if (status.running && (vm.guest_os == "windows" || vm.guest_os == "linux")) {
                    var checked = vm.vm_type == "libvirt"
                        ? GuestMemory.check_libvirt(vm.connection_uri, vm.resource_id, vm.guest_os == "windows")
                        : GuestMemory.check(vm.qmp_socket, vm.guest_os == "windows");
                    status.guest_memory_state = checked.state;
                    var guest = checked.memory;
                    if (guest != null) {
                        status.guest_ram_valid = true;
                        status.guest_ram_pct = guest.percent;
                        status.guest_ram_str = "%.2f GB / %.2f GB".printf(
                            guest.used_bytes / 1073741824.0, guest.total_bytes / 1073741824.0);
                    }
                }
                return status;
            }

            VmStatus st = VmStatus();
            st.running = false;
            st.cpu_pct = 0.0;
            st.ram_str = "0 MB";
            return st;
        }
    }
}
