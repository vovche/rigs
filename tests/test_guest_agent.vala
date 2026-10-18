namespace Rigs.Tests {
    public class TestGuestAgent {
        private class FakeCommands : HostCommand {
            public string output = "{\"return\":{\"name\":\"Microsoft Windows\",\"id\":\"mswindows\"}}";
            public int calls = 0;
            public bool rebooting = false;

            public FakeCommands() { base("native"); }

            public override CommandResult run(string[] argv, string? directory = null, uint timeout_ms = 3000) throws Error {
                calls++;
                assert(directory == null && timeout_ms == 5000);
                assert(argv.length == (rebooting ? 7 : 8));
                assert(argv[0] == "virsh" && argv[1] == "--connect" && argv[2] == "qemu:///session");
                assert(argv[3] == "qemu-agent-command" && argv[4] == "12345678-1234-1234-1234-123456789abc");
                var parser = new Json.Parser();
                parser.load_from_data(argv[argv.length - 1]);
                var request = parser.get_root().get_object();
                if (rebooting) {
                    assert(argv[5] == "--async");
                    assert(request.get_string_member("execute") == "guest-shutdown");
                    assert(request.get_object_member("arguments").get_string_member("mode") == "reboot");
                } else {
                    assert(argv[5] == "--timeout" && argv[6] == "5");
                    assert(request.get_string_member("execute") == "guest-get-osinfo");
                }
                return new CommandResult(output);
            }
        }

        private static VmModel domain() {
            var vm = new VmModel();
            vm.vm_type = "libvirt";
            vm.connection_uri = "qemu:///session";
            vm.resource_id = "12345678-1234-1234-1234-123456789abc";
            return vm;
        }

        public static void test_libvirt() {
            try {
                var host = new FakeCommands();
                var agent = new GuestAgent(host);
                var result = agent.command(domain(), "guest-get-osinfo");
                assert(result.get_object().get_string_member("name") == "Microsoft Windows");
                assert(host.calls == 1);
                host.rebooting = true;
                host.output = "";
                agent.reboot(domain());
                assert(host.calls == 2);
            } catch (Error e) { assert_not_reached(); }
        }

        private static void socket_peer(bool rebooting, bool error_reply = false) {
            try {
                string dir = DirUtils.make_tmp("rigs-qga-test-XXXXXX");
                string path = Path.build_filename(dir, "agent.sock");
                var listener = new SocketListener();
                listener.add_address(new UnixSocketAddress(path), SocketType.STREAM, SocketProtocol.DEFAULT, null, null);
                var peer = new Thread<void*>("fake-guest-agent", () => {
                    try {
                        var connection = listener.accept();
                        connection.socket.timeout = 1;
                        var input = new DataInputStream(connection.input_stream);
                        assert(input.read_byte() == 0xff);
                        var parser = new Json.Parser();
                        parser.load_from_data(input.read_line());
                        var request = parser.get_root().get_object();
                        assert(request.get_string_member("execute") == "guest-sync-delimited");
                        int64 token = request.get_object_member("arguments").get_int_member("id");
                        assert(token > 0);
                        size_t written;
                        uint8[] sentinel = { 0xff };
                        connection.output_stream.write_all("stale bytes without newline".data, out written);
                        connection.output_stream.write_all(sentinel, out written);
                        connection.output_stream.write_all("{\"return\":0}\n".data, out written);
                        connection.output_stream.write_all(sentinel, out written);
                        string sync = "{\"return\":%s}\n".printf(token.to_string());
                        connection.output_stream.write_all(sync.data, out written);
                        parser.load_from_data(input.read_line());
                        request = parser.get_root().get_object();
                        assert(request.get_string_member("execute") == (rebooting ? "guest-shutdown" : "guest-get-osinfo"));
                        if (rebooting) assert(request.get_object_member("arguments").get_string_member("mode") == "reboot");
                        else {
                            string reply = error_reply ? "{\"error\":{\"class\":\"GenericError\"}}\n" : "{\"return\":{\"id\":\"mswindows\"}}\n";
                            connection.output_stream.write_all(reply.data, out written);
                        }
                        connection.close();
                    } catch (Error e) { assert_not_reached(); }
                    return null;
                });
                var vm = new VmModel();
                vm.guest_agent_socket = path;
                // QGA must never accidentally use this unrelated QMP path.
                vm.qmp_socket = Path.build_filename(dir, "wrong-qmp.sock");
                bool rejected = false;
                try {
                    var agent = new GuestAgent();
                    if (rebooting) agent.reboot(vm);
                    else assert(agent.command(vm, "guest-get-osinfo").get_object().get_string_member("id") == "mswindows");
                } catch (Error e) { rejected = true; }
                peer.join();
                listener.close();
                FileUtils.unlink(path);
                DirUtils.remove(dir);
                assert(rejected == error_reply);
            } catch (Error e) { assert_not_reached(); }
        }

        public static void test_socket() {
            socket_peer(false);
            socket_peer(true);
            socket_peer(false, true);
        }

        public static void test_errors() {
            var host = new FakeCommands();
            var agent = new GuestAgent(host);
            string[] malformed = { "{}", "[]", "null", "{\"error\":{}}", "broken" };
            foreach (string text in malformed) {
                host.output = text;
                try {
                    agent.command(domain(), "guest-get-osinfo");
                    assert_not_reached();
                } catch (Error e) {}
            }
            int calls = host.calls;
            var invalid = domain();
            invalid.connection_uri = "qemu+ssh://remote/system";
            try { agent.command(invalid, "guest-get-osinfo"); assert_not_reached(); } catch (Error e) { assert(e is IOError.INVALID_ARGUMENT); }
            invalid = domain();
            invalid.resource_id = "--bad";
            try { agent.command(invalid, "guest-get-osinfo"); assert_not_reached(); } catch (Error e) { assert(e is IOError.INVALID_ARGUMENT); }
            try { agent.command(domain(), "guest-arbitrary"); assert_not_reached(); } catch (Error e) { assert(e is IOError.NOT_SUPPORTED); }
            try { agent.command(new VmModel(), "guest-ping"); assert_not_reached(); } catch (Error e) { assert(e is IOError.NOT_SUPPORTED); }
            assert(host.calls == calls);
            try {
                string dir = DirUtils.make_tmp("rigs-qga-timeout-XXXXXX");
                string path = Path.build_filename(dir, "agent.sock");
                var listener = new SocketListener();
                listener.add_address(new UnixSocketAddress(path), SocketType.STREAM, SocketProtocol.DEFAULT, null, null);
                var peer = new Thread<void*>("silent-guest-agent", () => {
                    try {
                        var connection = listener.accept();
                        Thread.usleep(50000);
                        connection.close();
                    } catch (Error e) { assert_not_reached(); }
                    return null;
                });
                var vm = new VmModel();
                vm.guest_agent_socket = path;
                try { agent.command(vm, "guest-ping", null, 10); assert_not_reached(); }
                catch (Error e) { assert(e is IOError.TIMED_OUT); }
                peer.join();
                listener.close();
                FileUtils.unlink(path);
                DirUtils.remove(dir);
            } catch (Error e) { assert_not_reached(); }
        }
    }
}
