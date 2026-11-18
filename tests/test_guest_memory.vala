using Rigs;

namespace Rigs.Tests {
    public class TestGuestMemory {
        private static GuestMemory? parse(string stats, int64 updated = 1000, bool windows = true, int64 now = 1000) {
            try {
                var parser = new Json.Parser();
                parser.load_from_data("{\"last-update\":%s,\"stats\":%s}".printf(updated.to_string(), stats));
                return GuestMemory.from_stats(parser.get_root().get_object(), windows, now);
            } catch (Error e) {
                assert_not_reached();
            }
        }

        public static void test_windows() {
            // The host can report 100%, but guest available RAM gives 45%.
            var ram = parse("{\"stat-total-memory\":4294967296,\"stat-free-memory\":2362232013,\"stat-available-memory\":3006477107}");
            assert(ram != null);
            assert((ram.percent - 45.0).abs() < 0.001);
            // Do not add the Windows driver's cache estimate to available RAM.
            var linux_ram = parse("{\"stat-total-memory\":1000,\"stat-free-memory\":100,\"stat-available-memory\":600}", 1000, false);
            assert(linux_ram != null && linux_ram.percent == 40.0);
            var idle = parse("{\"stat-total-memory\":1000,\"stat-free-memory\":1000}");
            assert(idle != null && idle.percent == 0.0);
            var full = parse("{\"stat-total-memory\":1000,\"stat-free-memory\":0}");
            assert(full != null && full.percent == 100.0);
        }

        public static void test_invalid() {
            string good = "{\"stat-total-memory\":1000,\"stat-free-memory\":550}";
            assert(parse(good, 0) == null);
            assert(parse(good, 984) == null);
            assert(parse(good, 1006) == null);
            assert(parse(good, 985) != null);
            assert(parse("{}") == null);
            assert(parse("{\"stat-total-memory\":0,\"stat-free-memory\":0}") == null);
            assert(parse("{\"stat-total-memory\":1000,\"stat-free-memory\":-1}") == null);
            assert(parse("{\"stat-total-memory\":1000,\"stat-free-memory\":18446744073709551615}") == null);
            assert(parse("{\"stat-total-memory\":1000,\"stat-free-memory\":1001}") == null);
            assert(parse("{\"stat-total-memory\":1000,\"stat-free-memory\":\"550\"}") == null);
            // Never treat Linux MemFree as MemAvailable.
            assert(parse(good, 1000, false) == null);
            assert(GuestMemory.read("", true) == null);
        }

        private static void fake_peer(bool error_reply, GuestMemoryState expected = GuestMemoryState.READY, string? timestamp_json = null) {
            try {
                string dir = DirUtils.make_tmp("rigs-qmp-test-XXXXXX");
                string path = Path.build_filename(dir, "qmp.sock");
                var listener = new SocketListener();
                listener.add_address(new UnixSocketAddress(path), SocketType.STREAM, SocketProtocol.DEFAULT, null, null);
                var peer = new Thread<void*>("fake-qmp", () => {
                    try {
                        var connection = listener.accept();
                        connection.socket.timeout = 1;
                        var input = new DataInputStream(connection.input_stream);
                        size_t written;
                        connection.output_stream.write_all("{\"QMP\":{}}\n".data, out written);
                        string[] names = {"qmp_capabilities", "qom-list", "qom-get", "qom-set"};
                        bool expect_set = expected == GuestMemoryState.GUEST_NOT_REPORTING || expected == GuestMemoryState.STALE;
                        for (int i = 0; i < 4; i++) {
                            string? line = input.read_line();
                            assert(line != null);
                            var parser = new Json.Parser();
                            parser.load_from_data(line);
                            var req = parser.get_root().get_object();
                            assert(req.get_string_member("execute") == names[i]);
                            int64 id = req.get_int_member("id");
                            string body = "{}";
                            if (i == 1) {
                                assert(req.get_object_member("arguments").get_string_member("path") == "/machine/peripheral");
                                body = expected == GuestMemoryState.DEVICE_MISSING ? "[]" : "[{\"name\":\"balloon0\"}]";
                            }
                            if (i == 3) {
                                var args = req.get_object_member("arguments");
                                assert(args.get_string_member("path") == "/machine/peripheral/balloon0");
                                assert(args.get_int_member("value") == 5);
                            }
                            if (i == 2) {
                                // A real QMP event can arrive before the reply.
                                connection.output_stream.write_all("{\"event\":\"BALLOON_CHANGE\"}\n".data, out written);
                                int64 updated = get_real_time() / 1000000;
                                if (expected == GuestMemoryState.GUEST_NOT_REPORTING) updated = 0;
                                if (expected == GuestMemoryState.STALE) updated -= 30;
                                string stats = expected == GuestMemoryState.UNSUPPORTED ? "{}" : "{\"stat-total-memory\":1000,\"stat-free-memory\":550}";
                                body = "{\"last-update\":%s,\"stats\":%s}".printf(updated.to_string(), stats);
                                if (timestamp_json != null) {
                                    body = timestamp_json.length == 0 ? "{\"stats\":{}}" :
                                        "{\"last-update\":%s,\"stats\":{}}".printf(timestamp_json);
                                }
                            }
                            string key = error_reply ? "error" : "return";
                            string reply = "{\"id\":%s,\"%s\":%s}\n".printf(id.to_string(), key, body);
                            connection.output_stream.write_all(reply.data, out written);
                            if (error_reply) break;
                            if (i == 1 && expected == GuestMemoryState.DEVICE_MISSING) break;
                            if (i == 2 && !expect_set) break;
                        }
                        connection.close();
                    } catch (Error e) { assert_not_reached(); }
                    return null;
                });
                var result = GuestMemory.check(path, true);
                peer.join();
                listener.close();
                FileUtils.unlink(path);
                DirUtils.remove(dir);
                if (error_reply) assert(result.state == GuestMemoryState.CONNECTION_UNAVAILABLE && result.memory == null);
                else {
                    assert(result.state == expected);
                    if (expected == GuestMemoryState.READY) assert(result.memory != null && result.memory.percent == 45.0);
                    else assert(result.memory == null);
                }
                assert(GuestMemory.read(path, true) == null);
            } catch (Error e) { assert_not_reached(); }
        }

        public static void test_qmp() { fake_peer(false); }
        public static void test_qmp_error() { fake_peer(true); }

        public static void test_states() {
            assert(GuestMemory.check("", true).state == GuestMemoryState.NOT_CONFIGURED);
            fake_peer(false, GuestMemoryState.DEVICE_MISSING);
            fake_peer(false, GuestMemoryState.GUEST_NOT_REPORTING);
            fake_peer(false, GuestMemoryState.STALE);
            fake_peer(false, GuestMemoryState.UNSUPPORTED);
            fake_peer(false, GuestMemoryState.UNSUPPORTED, "");
            fake_peer(false, GuestMemoryState.UNSUPPORTED, "\"invalid\"");
        }

        private class FakeCommands : HostCommand {
            public string stats;
            public int status = 0;
            public int calls = 0;
            public int fail_on_call = 1;

            public FakeCommands(string stats) {
                base.with_mode(ExecutionMode.NATIVE);
                this.stats = stats;
            }

            public override CommandResult run(string[] argv, string? directory = null, uint timeout_ms = 3000) throws Error {
                assert(argv.length == (calls == 0 ? 5 : 8));
                assert(argv[0] == "virsh" && argv[1] == "--connect");
                assert(argv[2] == "qemu:///session" && argv[3] == "dommemstat");
                assert(argv[4] == "12345678-1234-1234-1234-123456789abc");
                assert(directory == null && timeout_ms == 3000);
                if (calls == 1) assert(argv[5] == "--period" && argv[6] == "5" && argv[7] == "--live");
                calls++;
                return new CommandResult(stats, "", calls >= fail_on_call ? status : 0);
            }
        }

        public static void test_libvirt() {
            string uuid = "12345678-1234-1234-1234-123456789abc";
            string fresh = "last_update %s\n".printf((get_real_time() / 1000000).to_string());
            var host = new FakeCommands(fresh + "available 1000\nunused 550\nusable 700\nactual 9000\nrss 8000\n");
            var result = GuestMemory.check_libvirt("qemu:///session", uuid, true, host);
            // Fresh statistics: read only, never touch the VM's polling setting.
            assert(host.calls == 1 && result.state == GuestMemoryState.READY);
            assert(result.memory != null && result.memory.percent == 45.0 && result.memory.total_bytes == 1024000);
            host.calls = 0;
            result = GuestMemory.check_libvirt("qemu:///session", uuid, false, host);
            assert(result.state == GuestMemoryState.READY && result.memory != null && result.memory.percent == 30.0);
            string[] unavailable = { "", "last_update 0\navailable 1000\nunused 550\n" };
            foreach (string stats in unavailable) {
                host.stats = stats;
                host.calls = 0;
                assert(GuestMemory.check_libvirt("qemu:///session", uuid, true, host).state == GuestMemoryState.GUEST_NOT_REPORTING);
            }
            host.stats = "last_update 1\navailable 1000\nunused 550\n";
            host.calls = 0;
            assert(GuestMemory.check_libvirt("qemu:///session", uuid, true, host).state == GuestMemoryState.STALE);
            host.stats = fresh + "actual 1000\nrss 550\n";
            host.calls = 0;
            assert(GuestMemory.check_libvirt("qemu:///session", uuid, true, host).state == GuestMemoryState.UNSUPPORTED);
            host.status = 1;
            host.calls = 0;
            assert(GuestMemory.check_libvirt("qemu:///session", uuid, true, host).state == GuestMemoryState.CONNECTION_UNAVAILABLE);
            assert(host.calls == 1);
            host.fail_on_call = 2;
            host.stats = "last_update 0\navailable 1000\nunused 550\n";
            host.calls = 0;
            assert(GuestMemory.check_libvirt("qemu:///session", uuid, true, host).state == GuestMemoryState.CONNECTION_UNAVAILABLE);
            assert(host.calls == 2);
            host.calls = 0;
            assert(GuestMemory.check_libvirt("qemu+ssh://remote/system", uuid, true, host).state == GuestMemoryState.NOT_CONFIGURED);
            assert(GuestMemory.check_libvirt("qemu:///session", "--domain=bad", true, host).state == GuestMemoryState.NOT_CONFIGURED);
            assert(host.calls == 0);
        }
    }
}
