/* guest_memory.vala — Optional, read-only guest RAM telemetry over local QMP. */
namespace Rigs {
    public class GuestMemory : Object {
        public int64 total_bytes;
        public int64 used_bytes;
        public double percent { get { return 100.0 * used_bytes / total_bytes; } }

        private static int64 counter(Json.Object obj, string key) {
            if (!obj.has_member(key)) return -1;
            var node = obj.get_member(key);
            if (node.get_node_type() != Json.NodeType.VALUE || node.get_value_type() != typeof(int64)) return -1;
            return node.get_int();
        }

        public static GuestMemory? from_stats(Json.Object data, bool windows, int64 now) {
            int64 updated = counter(data, "last-update");
            if (updated <= 0 || updated > now + 5 || now - updated > 15) return null;
            if (!data.has_member("stats") || data.get_member("stats").get_node_type() != Json.NodeType.OBJECT) return null;
            var stats = data.get_object_member("stats");
            int64 total = counter(stats, "stat-total-memory");
            // VirtIO-Win's MEMFREE is GlobalMemoryStatusEx.ullAvailPhys.
            // Its AVAIL adds a cache estimate, so use MEMFREE for Windows.
            // Linux MEMFREE excludes reclaimable cache: require MemAvailable.
            int64 available = counter(stats, windows ? "stat-free-memory" : "stat-available-memory");
            if (total <= 0 || available < 0 || available > total) return null;
            var result = new GuestMemory();
            result.total_bytes = total;
            result.used_bytes = total - available;
            return result;
        }

        private class Client : Object {
            private SocketConnection connection;
            private DataInputStream input;
            private int64 deadline;
            private int sequence = 0;

            public Client(string path) throws Error {
                var client = new SocketClient();
                client.timeout = 1;
                connection = client.connect(new UnixSocketAddress(path));
                connection.socket.timeout = 1;
                input = new DataInputStream(connection.input_stream);
                deadline = get_monotonic_time() + 1000000;
                var greeting = receive();
                if (!greeting.has_member("QMP")) throw new IOError.INVALID_DATA("Missing QMP greeting");
            }

            ~Client() {
                if (connection != null) {
                    try { connection.close(); } catch (Error e) { }
                }
            }

            private Json.Object receive() throws Error {
                if (get_monotonic_time() > deadline) throw new IOError.TIMED_OUT("QMP timeout");
                // Bound frames even when a peer never terminates a line.
                var line = new StringBuilder();
                while (line.len < 65536) {
                    if (get_monotonic_time() > deadline) throw new IOError.TIMED_OUT("QMP timeout");
                    uint8 c = input.read_byte();
                    if (c == '\n') {
                        var parser = new Json.Parser();
                        parser.load_from_data(line.str);
                        var root = parser.get_root();
                        if (root == null || root.get_node_type() != Json.NodeType.OBJECT)
                            throw new IOError.INVALID_DATA("Invalid QMP frame");
                        return root.get_object();
                    }
                    line.append_c((char)c);
                }
                throw new IOError.INVALID_DATA("QMP frame too large");
            }

            public Json.Node command(string name, Json.Object? args = null) throws Error {
                int id = ++sequence;
                var request = new Json.Object();
                request.set_string_member("execute", name);
                request.set_int_member("id", id);
                if (args != null) request.set_object_member("arguments", args);
                var node = new Json.Node(Json.NodeType.OBJECT);
                node.set_object(request);
                var generator = new Json.Generator();
                generator.set_root(node);
                string payload = generator.to_data(null) + "\n";
                size_t written;
                connection.output_stream.write_all(payload.data, out written);
                for (int i = 0; i < 16; i++) {
                    var response = receive();
                    if (response.has_member("event")) continue;
                    if (counter(response, "id") != id) continue;
                    if (response.has_member("error") || !response.has_member("return"))
                        throw new IOError.FAILED("QMP command failed");
                    return response.get_member("return");
                }
                throw new IOError.INVALID_DATA("No matching QMP reply");
            }
        }

        public static GuestMemory? read(string socket_path, bool windows) {
            if (socket_path.length == 0) return null;
            try {
                var client = new Client(socket_path);
                client.command("qmp_capabilities");
                var args = new Json.Object();
                args.set_string_member("path", "/machine/peripheral/balloon0");
                args.set_string_member("property", "guest-stats-polling-interval");
                args.set_int_member("value", 5);
                client.command("qom-set", args);
                args = new Json.Object();
                args.set_string_member("path", "/machine/peripheral/balloon0");
                args.set_string_member("property", "guest-stats");
                var result = client.command("qom-get", args);
                if (result.get_node_type() != Json.NodeType.OBJECT) return null;
                return from_stats(result.get_object(), windows, get_real_time() / 1000000);
            } catch (Error e) {
                // Missing device, disconnected socket and stale stats are all
                // an unavailable guest metric, never a host-memory fallback.
                return null;
            }
        }
    }
}
