namespace Rigs {
    public class GuestAgent : Object {
        private HostCommand commands;

        public GuestAgent(HostCommand? commands = null) {
            this.commands = commands ?? new HostCommand();
        }

        private static string serialize(string name, Json.Object? args) {
            var obj = new Json.Object();
            obj.set_string_member("execute", name);
            if (args != null) obj.set_object_member("arguments", args);
            var node = new Json.Node(Json.NodeType.OBJECT);
            node.set_object(obj);
            var generator = new Json.Generator();
            generator.set_root(node);
            return generator.to_data(null);
        }

        private static Json.Node response(string text) throws Error {
            var parser = new Json.Parser();
            parser.load_from_data(text);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT)
                throw new IOError.INVALID_DATA("Invalid guest agent envelope.");
            var obj = root.get_object();
            if (obj.has_member("error")) throw new IOError.FAILED("Guest agent rejected the request.");
            if (!obj.has_member("return")) throw new IOError.INVALID_DATA("Missing guest agent result.");
            return obj.get_member("return").copy();
        }

        private static void validate_name(string name) throws Error {
            switch (name) {
                case "guest-info": case "guest-get-osinfo": case "guest-get-devices":
                case "guest-exec": case "guest-exec-status": case "guest-file-open":
                case "guest-file-write": case "guest-file-read": case "guest-file-close":
                case "guest-ping": case "guest-shutdown": return;
                default: throw new IOError.NOT_SUPPORTED("Unsupported guest agent operation.");
            }
        }

        private class Deadline : Object {
            public Mutex mutex = Mutex();
            public Cond cond = Cond();
            public bool finished = false;
            public bool expired = false;
        }

        private static string read_frame(DataInputStream input, Cancellable cancel, ref uint scanned) throws Error {
            var line = new StringBuilder();
            while (line.len < 1024 * 1024) {
                uint8 value = input.read_byte(cancel);
                scanned++;
                if (scanned > 2 * 1024 * 1024) throw new IOError.INVALID_DATA("Guest agent synchronization limit exceeded.");
                if (value == '\n') return line.str;
                line.append_c((char)value);
            }
            throw new IOError.INVALID_DATA("Guest agent frame exceeds size limit.");
        }

        private static Json.Node socket_exchange(string path, string payload, uint timeout_ms, bool no_reply) throws Error {
            if (path.length == 0) throw new IOError.NOT_SUPPORTED("Configure a dedicated guest agent socket first.");
            var cancel = new Cancellable();
            var deadline = new Deadline();
            int64 end = get_monotonic_time() + (int64)timeout_ms * 1000;
            var watchdog = new Thread<void*>("guest-agent-deadline", () => {
                deadline.mutex.lock();
                while (!deadline.finished) {
                    if (!deadline.cond.wait_until(deadline.mutex, end) && !deadline.finished) {
                        deadline.expired = true;
                        cancel.cancel();
                        break;
                    }
                }
                deadline.mutex.unlock();
                return null;
            });
            SocketConnection? connection = null;
            Json.Node? result = null;
            Error? failure = null;
            try {
                var client = new SocketClient();
                connection = client.connect(new UnixSocketAddress(path), cancel);
                var input = new DataInputStream(connection.input_stream);
                int64 token = ((int64)Random.next_int() << 31) | (int64)(Random.next_int() & 0x7fffffff);
                if (token == 0) token = 1;
                var args = new Json.Object();
                args.set_int_member("id", token);
                uint8[] sentinel = { 0xff };
                size_t written;
                connection.output_stream.write_all(sentinel, out written, cancel);
                string sync = serialize("guest-sync-delimited", args) + "\n";
                connection.output_stream.write_all(sync.data, out written, cancel);
                uint scanned = 0;
                bool matched = false;
                while (scanned < 2 * 1024 * 1024) {
                    uint8 value = input.read_byte(cancel);
                    scanned++;
                    if (value != 0xff) continue;
                    string frame = read_frame(input, cancel, ref scanned);
                    try {
                        var candidate = response(frame);
                        if (candidate.get_node_type() == Json.NodeType.VALUE && candidate.get_value_type() == typeof(int64) && candidate.get_int() == token) {
                            matched = true;
                            break;
                        }
                    } catch (Error e) {
                        // Previous clients may leave partial replies; only our token synchronizes.
                    }
                }
                if (!matched) throw new IOError.INVALID_DATA("Guest agent synchronization failed.");
                string request = payload + "\n";
                connection.output_stream.write_all(request.data, out written, cancel);
                if (no_reply) result = new Json.Node(Json.NodeType.NULL);
                else {
                    scanned = 0;
                    result = response(read_frame(input, cancel, ref scanned));
                }
            } catch (Error e) { failure = e; }
            deadline.mutex.lock();
            deadline.finished = true;
            deadline.cond.signal();
            deadline.mutex.unlock();
            watchdog.join();
            if (connection != null) {
                try { connection.close(); } catch (Error e) {}
            }
            if (deadline.expired) throw new IOError.TIMED_OUT("Guest agent request timed out.");
            if (failure != null) throw failure;
            if (result == null) throw new IOError.INVALID_DATA("Missing guest agent response.");
            return result;
        }

        private Json.Node invoke(Resource resource, string name, Json.Object? args, uint timeout_ms, bool no_reply) throws Error {
            validate_name(name);
            string payload = serialize(name, args);
            if (resource.kind != "libvirt")
                return socket_exchange(resource.guest_agent_socket, payload, timeout_ms, no_reply);
            if ((resource.connection_uri != "qemu:///session" && resource.connection_uri != "qemu:///system") ||
                !Regex.match_simple("\\A[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}\\z", resource.resource_id))
                throw new IOError.INVALID_ARGUMENT("Guest agent requires a local libvirt connection and valid domain UUID.");
            uint seconds = timeout_ms / 1000 + (timeout_ms % 1000 > 0 ? 1 : 0);
            if (seconds == 0) seconds = 1;
            string[] argv = { "virsh", "--connect", resource.connection_uri, "qemu-agent-command", resource.resource_id };
            if (no_reply) argv += "--async";
            else { argv += "--timeout"; argv += seconds.to_string(); }
            argv += payload;
            var reply = commands.run(argv, null, timeout_ms);
            if (reply.exit_status != 0) throw new IOError.FAILED("Cannot communicate with the libvirt guest agent.");
            if (no_reply) return new Json.Node(Json.NodeType.NULL);
            if (reply.output.length > 1024 * 1024) throw new IOError.INVALID_DATA("Guest agent frame exceeds size limit.");
            return response(reply.output);
        }

        public virtual Json.Node command(Resource resource, string name, Json.Object? args = null, uint timeout_ms = 5000) throws Error {
            return invoke(resource, name, args, timeout_ms, false);
        }

        public virtual void reboot(Resource resource) throws Error {
            var args = new Json.Object();
            args.set_string_member("mode", "reboot");
            invoke(resource, "guest-shutdown", args, 5000, true);
        }
    }
}
