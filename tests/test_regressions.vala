/* test_regressions.vala — one test per defect class found in review.
 * When you fix a bug, add its reproduction here (see docs/guardrails.md). */
using Rigs;

namespace Rigs.Tests {
    private class CountingTarget : Object, SearchTarget {
        public int depth = 0;
        public int max_depth = 0;
        public GenericArray<VmModel> get_vms() { assert(depth > 0); return new GenericArray<VmModel>(); }
        public void focus_vm(string id) { assert(depth > 0); }
        public void set_search_query(string query) { assert(depth > 0); }
        public void begin_query() { depth++; max_depth = int.max(max_depth, depth); }
        public void end_query() { depth--; }
    }

    // Scripted host: run_capture_tail returns tail_result (or throws tail_error); run answers by argv[0..1].
    private class ScriptedCommands : HostCommand {
        public CommandResult tail_result = new CommandResult();
        public Error? tail_error = null;
        public Error? run_error = null;
        public string domstate = "running\n";
        public GenericArray<string> calls = new GenericArray<string>();

        public ScriptedCommands() { base("native"); }

        public override CommandResult run_capture_tail(string[] argv, string? directory = null) throws Error {
            calls.add(string.joinv("|", argv));
            if (tail_error != null) throw tail_error;
            return tail_result;
        }

        public override CommandResult run(string[] argv, string? directory = null, uint timeout_ms = 3000) throws Error {
            calls.add(string.joinv("|", argv));
            if (run_error != null) throw run_error;
            if (argv[0] == "virsh" && argv[3] == "domstate") return new CommandResult(domstate, "", 0);
            return new CommandResult("", "", 0);
        }
    }

    public class TestRegressions {
        // Class: data concatenated into a command language (shell, HMP).
        public static void test_hmp_quoting() {
            try {
                assert(HmpMonitor.quote("/isos/win.iso") == "\"/isos/win.iso\"");
                assert(HmpMonitor.quote("/a b/it's \"x\"\\.iso") == "\"/a b/it's \\\"x\\\"\\\\.iso\"");
            } catch (Error e) { assert_not_reached(); }
            foreach (string bad in new string[] { "/x.iso\nquit", "/x.iso\r", "/x\t.iso" }) {
                bool refused = false;
                try { HmpMonitor.quote(bad); } catch (Error e) { refused = true; }
                assert(refused);
            }
            bool refused = false;
            try { HmpMonitor.validate_command("eject -f cdrom\nquit"); } catch (Error e) { refused = true; }
            assert(refused);
        }

        public static void test_hmp_send() {
            try {
                string dir = DirUtils.make_tmp("rigs-hmp-XXXXXX");
                string path = Path.build_filename(dir, "monitor.sock");
                var listener = new SocketListener();
                listener.add_address(new UnixSocketAddress(path), SocketType.STREAM, SocketProtocol.DEFAULT, null, null);
                string? received = null;
                var peer = new Thread<void*>("fake-hmp", () => {
                    try {
                        var c = listener.accept();
                        size_t w;
                        c.output_stream.write_all("QEMU 9.0 monitor - type 'help'\r\n(qemu) ".data, out w);
                        received = new DataInputStream(c.input_stream).read_line();
                        c.output_stream.write_all("change ...\r\n(qemu) ".data, out w);
                        c.close();
                    } catch (Error e) { assert_not_reached(); }
                    return null;
                });
                string command = "change cdrom " + HmpMonitor.quote("/tmp/x'; touch /tmp/pwn; '.iso");
                HmpMonitor.send(path, command);
                peer.join();
                listener.close();
                FileUtils.unlink(path);
                DirUtils.remove(dir);
                assert(received == "change cdrom \"/tmp/x'; touch /tmp/pwn; '.iso\"");
            } catch (Error e) { assert_not_reached(); }
        }

        // Class: process lookup by shell-parsed pattern (pgrep via spawn_command_line).
        private static void fake_process(string root, int pid, string[] argv, string state, int rss_pages) {
            string dir = Path.build_filename(root, pid.to_string());
            DirUtils.create_with_parents(dir, 0700);
            var cmd = new ByteArray();
            foreach (string a in argv) { cmd.append(a.data); cmd.append({ 0 }); }
            try {
                FileUtils.set_data(Path.build_filename(dir, "cmdline"), cmd.data);
                FileUtils.set_contents(Path.build_filename(dir, "status"), "Name:\tx\nState:\t%s (x)\n".printf(state));
                FileUtils.set_contents(Path.build_filename(dir, "statm"), "%d %d 0 0 0 0 0\n".printf(rss_pages * 2, rss_pages));
                FileUtils.set_contents(Path.build_filename(dir, "stat"),
                    "%d (qemu x) S 1 1 1 0 -1 0 0 0 0 0 100 50 0 0 20 0 1 0\n".printf(pid));
            } catch (Error e) { assert_not_reached(); }
        }

        private static void remove_tree(string path) {
            try {
                var dir = Dir.open(path);
                string? name;
                while ((name = dir.read_name()) != null) {
                    string child = Path.build_filename(path, name);
                    if (FileUtils.test(child, FileTest.IS_DIR)) remove_tree(child); else FileUtils.unlink(child);
                }
            } catch (Error e) { }
            DirUtils.remove(path);
        }

        public static void test_find_vm_pid() {
            try {
                string root = DirUtils.make_tmp("rigs-proc-XXXXXX");
                string name = "qemu-system-x86_64 -name win10";
                fake_process(root, 10, { "/bin/bash", "-c", "exec " + name }, "S", 100);       // wrapper
                fake_process(root, 11, { "qemu-system-x86_64", "-name", "win10", "-m", "4G" }, "S", 50000);
                fake_process(root, 12, { "qemu-system-x86_64", "-name", "win10" }, "Z", 90000); // zombie
                fake_process(root, 13, { "qemu-system-x86_64", "-name", "win10" }, "S", 99999); // "self"
                fake_process(root, 14, {}, "S", 99999);                                         // kernel thread
                FileUtils.set_contents(Path.build_filename(root, "stat"), "cpu  100 0 100 800 0 0 0 0\n");
                // Spaces and quotes in the pattern are literal, never parsed.
                assert(QemuDriver.find_vm_pid(root, name, 13) == 11);
                assert(QemuDriver.find_vm_pid(root, "win10'\"", 13) == -1);
                assert(QemuDriver.find_vm_pid(root, "   ", 13) == -1);
                assert(QemuDriver.find_vm_pid(root + "/missing", name, 13) == -1);

                var driver = new QemuDriver();
                driver.proc_root = root;
                var vm = new VmModel();
                vm.id = "win10";
                vm.process_name = "-name win10 -m";
                if (new HostCommand().mode == "native") {
                    var st = driver.check_status(vm);
                    assert(st.running && st.status_available);
                    // "-m 4G" is read from the NUL-separated cmdline (it used to be truncated at argv[0]).
                    assert(st.ram_str.has_suffix("/ 4.0 GB"));
                }
                remove_tree(root);
            } catch (Error e) { assert_not_reached(); }
        }

        // Class: unsigned counter subtraction and inconsistent percentage scales.
        public static void test_metrics() {
            assert(Metrics.saturating_delta(10, 5) == 0);
            assert(Metrics.busy_percent(500, 1000, 600, 1100) == 0.0);
            assert(Metrics.busy_percent(500, 1000, 550, 1100) == 50.0);
            // iowait went backwards: idle smaller than before must not wrap to ~1.8e19.
            double pct = Metrics.busy_percent(900, 1000, 100, 1100);
            assert(pct >= 0.0 && pct <= 100.0);
            assert(Metrics.busy_percent(0, 1000, 0, 1000) == 0.0);
            assert(Metrics.delta_percent(10, 5, 100, 200) == 0.0);
            assert(Metrics.delta_percent(0, 50, 0, 100) == 50.0);
            assert(Metrics.container_cpu_share("250%", 4) == 62.5);
            assert(Metrics.container_cpu_share("900%", 4) == 100.0);
            assert(Metrics.container_cpu_share("--", 4) == 0.0);
            assert(Metrics.container_cpu_share("-3%", 4) == 0.0);
        }

        public static void test_parse_mem() {
            assert(ConfigManager.parse_mem_to_mb("4096") == 4096.0);
            assert(ConfigManager.parse_mem_to_mb("4G") == 4096.0);
            assert(ConfigManager.parse_mem_to_mb("4GiB") == 4096.0);
            assert(ConfigManager.parse_mem_to_mb(" 512m ") == 512.0);
            assert(ConfigManager.parse_mem_to_mb("1T") == 1048576.0);
            assert(ConfigManager.parse_mem_to_mb("size=4G,maxmem=8G") == 0.0);
            assert(ConfigManager.parse_mem_to_mb("") == 0.0);
            assert(ConfigManager.parse_mem_to_mb("G") == 0.0);
        }

        // Class: waiting on pipes that background children inherit; unbounded/invalid output.
        public static void test_capture_tail() {
            try {
                var host = new HostCommand("native");
                int64 started = get_monotonic_time();
                var r = host.run_capture_tail({ "/bin/bash", "-c", "sleep 2 & echo out; echo err >&2; exit 3" });
                assert(get_monotonic_time() - started < 1000000);
                assert(r.exit_status == 3);
                assert(r.error_output.contains("out") && r.error_output.contains("err"));
                r = host.run_capture_tail({ "/bin/bash", "-c", "head -c 200000 /dev/zero | tr '\\0' a; printf '\\377END'" });
                assert(r.error_output.length <= HostCommand.CAPTURE_TAIL_BYTES * 3);
                assert(r.error_output.has_suffix("END") && r.error_output.validate());
                r = host.run({ "/bin/bash", "-c", "printf '\\377ok'; printf '\\376' >&2" });
                assert(r.output.validate() && r.output.has_suffix("ok") && r.error_output.validate());
            } catch (Error e) { assert_not_reached(); }
        }

        // Class: interface methods with default bodies silently not implemented.
        public static void test_search_target_balanced() {
            var target = new CountingTarget();
            var provider = new SearchProvider(target);
            try {
                provider.get_initial_result_set({ "x" });
                provider.get_subsearch_result_set({}, { "x" });
                provider.get_result_metas({ "a" });
                provider.activate_result("a", {}, 0);
                provider.launch_search({ "x" }, 0);
            } catch (Error e) { assert_not_reached(); }
            assert(target.depth == 0 && target.max_depth == 1);
        }
        // Class: failures logged with warning() where the user never sees them.
        public static void test_hmp_command_output() {
            assert(HmpMonitor.command_output("QEMU 9.0 monitor\r\n(qemu) change cdrom \"/x\"\r\n(qemu) ") == "");
            assert(HmpMonitor.command_output("(qemu) \x1b[Keject -f cdrom\r\nDevice 'cdrom' not found\r\n(qemu) ")
                == "Device 'cdrom' not found");
            assert(HmpMonitor.command_output("(qemu) system_powerdown") == ""); // no second prompt: unknown
        }

        public static void test_error_to_issue() {
            var timeout = StartupDiagnostics.from_error(new IOError.TIMED_OUT("slow"), ResourceOperation.STOP);
            assert(timeout.category == FailureCategory.TIMEOUT && timeout.operation == ResourceOperation.STOP);
            var missing = StartupDiagnostics.from_error(new SpawnError.NOENT("podman: not found"));
            assert(missing.category == FailureCategory.MISSING_PROGRAM && missing.operation == ResourceOperation.START);
            var unsupported = StartupDiagnostics.from_error(new IOError.NOT_SUPPORTED("Restricted Snap"));
            assert(unsupported.category == FailureCategory.UNSUPPORTED && unsupported.description == "Restricted Snap");
            var other = StartupDiagnostics.from_error(new IOError.FAILED("QEMU: boom"), ResourceOperation.MEDIA);
            assert(other.matched_snippet == "QEMU: boom");
            foreach (var op in new ResourceOperation[] { ResourceOperation.START, ResourceOperation.STOP,
                    ResourceOperation.CONNECT, ResourceOperation.MEDIA, ResourceOperation.RUN })
                assert(StartupDiagnostics.headline(op, "vm1").contains("vm1"));
            var host = new ScriptedCommands();
            host.run_error = new IOError.TIMED_OUT("slow");
            var stop = StartupDiagnostics.check_command(host, { "/bin/bash", "-c", "x" }, null, ResourceOperation.STOP, 1000);
            assert(stop != null && stop.operation == ResourceOperation.STOP && stop.category == FailureCategory.TIMEOUT);
            host.run_error = null;
            assert(StartupDiagnostics.check_command(host, { "true" }, null, ResourceOperation.STOP, 1000) == null);
            host.tail_result = new CommandResult("", "remote-viewer: cannot connect\n", 1);
            var connect = StartupDiagnostics.check_command(host, { "x" }, null, ResourceOperation.CONNECT);
            assert(connect != null && connect.operation == ResourceOperation.CONNECT);
        }

        public static void test_qemu_start_failures() {
            string root = "";
            try { root = DirUtils.make_tmp("rigs-proc-XXXXXX"); } catch (Error e) { assert_not_reached(); }
            var host = new ScriptedCommands();
            var driver = new QemuDriver(host);
            driver.proc_root = root;
            driver.settle_ms = 0;
            var vm = new VmModel();
            vm.id = "win10";
            vm.start_cmd = "./run-vm.sh";
            // Script fails: diagnosed from its own output.
            host.tail_result = new CommandResult("", "qemu-system-x86_64: Could not access KVM kernel module\n", 1);
            var issue = driver.start_blocking(vm);
            assert(issue != null && issue.category == FailureCategory.PERMISSIONS_KVM && issue.operation == ResourceOperation.START);
            // Spawning itself fails.
            host.tail_error = new SpawnError.NOENT("bash missing");
            issue = driver.start_blocking(vm);
            assert(issue != null && issue.category == FailureCategory.MISSING_PROGRAM);
            host.tail_error = null;
            // Script succeeded (daemonized QEMU) but no matching process exists.
            host.tail_result = new CommandResult("", "", 0);
            vm.process_name = "-name win10";
            issue = driver.start_blocking(vm);
            assert(issue != null && issue.matched_snippet.contains("-name win10"));
            // ...and with the process present there is nothing to report.
            fake_process(root, 21, { "qemu-system-x86_64", "-name", "win10" }, "S", 1000);
            assert(driver.start_blocking(vm) == null);
            // Without process_name nothing can be checked: no false alarm.
            vm.process_name = "";
            assert(driver.start_blocking(vm) == null);
            // A late nonzero exit (foreground VM crashed) is reported as RUN, not START.
            driver.startup_window_us = 0;
            host.tail_result = new CommandResult("", "qemu: terminating on signal 11\n", 139);
            issue = driver.start_blocking(vm);
            assert(issue != null && issue.operation == ResourceOperation.RUN);
            remove_tree(root);
        }

        public static void test_managed_start_failures() {
            var host = new ScriptedCommands();
            var libvirt = new ManagedDriver("libvirt", host);
            libvirt.settle_ms = 0;
            var vm = new VmModel();
            vm.resource_id = "01234567-89ab-cdef-0123-456789abcdef";
            vm.connection_uri = "qemu:///session";
            assert(libvirt.start_blocking(vm) == null);
            host.domstate = "shut off (failed)\n";
            var issue = libvirt.start_blocking(vm);
            assert(issue != null && issue.matched_snippet == "shut off (failed)");
            assert(issue.suggested_command.has_prefix("virsh --connect qemu:///session dominfo "));
            host.run_error = new IOError.TIMED_OUT("virsh hung");
            issue = libvirt.start_blocking(vm);
            assert(issue != null && issue.category == FailureCategory.TIMEOUT);
        }

        public static void test_save_failure_reported() {
            ConfigManager.load_error = "broken";
            assert(!ConfigManager.save_vms(new GenericArray<VmModel>()));
            assert(ConfigManager.save_error != null);
            ConfigManager.load_error = null;
        }
    }
}
