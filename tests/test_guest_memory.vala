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

        private static void fake_peer(bool error_reply) {
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
                        string[] names = {"qmp_capabilities", "qom-set", "qom-get"};
                        for (int i = 0; i < 3; i++) {
                            string? line = input.read_line();
                            assert(line != null);
                            var parser = new Json.Parser();
                            parser.load_from_data(line);
                            var req = parser.get_root().get_object();
                            assert(req.get_string_member("execute") == names[i]);
                            int64 id = req.get_int_member("id");
                            string body = "{}";
                            if (i == 1) {
                                var args = req.get_object_member("arguments");
                                assert(args.get_string_member("path") == "/machine/peripheral/balloon0");
                                assert(args.get_int_member("value") == 5);
                            }
                            if (i == 2) {
                                // A real QMP event can arrive before the reply.
                                connection.output_stream.write_all("{\"event\":\"BALLOON_CHANGE\"}\n".data, out written);
                                body = "{\"last-update\":%s,\"stats\":{\"stat-total-memory\":1000,\"stat-free-memory\":550}}".printf((get_real_time() / 1000000).to_string());
                            }
                            string key = error_reply ? "error" : "return";
                            string reply = "{\"id\":%s,\"%s\":%s}\n".printf(id.to_string(), key, body);
                            connection.output_stream.write_all(reply.data, out written);
                            if (error_reply) break;
                        }
                        connection.close();
                    } catch (Error e) { assert_not_reached(); }
                    return null;
                });
                var result = GuestMemory.read(path, true);
                peer.join();
                listener.close();
                FileUtils.unlink(path);
                DirUtils.remove(dir);
                if (error_reply) assert(result == null);
                else assert(result != null && result.percent == 45.0);
                assert(GuestMemory.read(path, true) == null);
            } catch (Error e) { assert_not_reached(); }
        }

        public static void test_qmp() { fake_peer(false); }
        public static void test_qmp_error() { fake_peer(true); }
    }
}
