using Rigs;
namespace Rigs.Tests {
    private class MediaCommands : HostCommand {
        public GenericArray<string> calls = new GenericArray<string>();
        public string blocks = "Type Device Target Source\n--------------------------------\nfile disk vda /data/system.qcow2\nfile cdrom sda -\nfile cdrom sdb /data/installer with spaces.iso\n";
        public string mounts = "[]";
        public override CommandResult run(string[] argv, string? directory = null, uint timeout_ms = 3000) throws Error {
            calls.add(string.joinv("|", argv));
            if (argv[0] == "virsh" && argv[3] == "domblklist") return new CommandResult(blocks);
            if (argv[0] == "podman" || argv[0] == "docker") return new CommandResult(mounts);
            return new CommandResult();
        }
    }

    private class FakeMedia : GuestMedia {
        public string blocks = "[{\"device\":\"disk0\",\"removable\":false},{\"device\":\"floppy0\",\"removable\":true},{\"device\":\"cd0\",\"removable\":true,\"tray_open\":false},{\"device\":\"cd1\",\"removable\":true,\"tray_open\":false,\"inserted\":{\"file\":\"/occupied.iso\"}}]";
        public GenericArray<string> calls = new GenericArray<string>();
        public Json.Object? arguments;
        public Json.Object? image;
        public Json.Object? opening;
        public Json.Object? insertion;
        public string fail_on = "";
        public FakeMedia(HostCommand? commands = null) { base(commands); }
        public override Json.Node qmp(Resource resource, string name, Json.Object? args = null) throws Error {
            calls.add(name);
            if (args != null) arguments = args;
            if (name == "blockdev-add") image = args;
            if (name == "blockdev-open-tray") opening = args;
            if (name == "blockdev-insert-medium") insertion = args;
            if (name == fail_on) throw new IOError.FAILED("Injected QMP failure.");
            var parser = new Json.Parser();
            parser.load_from_data(name == "query-block" ? blocks : "{}");
            return parser.get_root().copy();
        }
    }

    public class TestGuestMedia {
        private static string make_iso(string directory) throws Error {
            string path = Path.build_filename(directory, "driver image.iso");
            uint8[] data = new uint8[32774];
            data[32769] = 'C'; data[32770] = 'D'; data[32771] = '0'; data[32772] = '0'; data[32773] = '1';
            FileUtils.set_data(path, data);
            return path;
        }

        private static void check_qmp_client(string directory) throws Error {
            // Exercise the real client against a private fixture socket, never a VM.
            string socket_path = Path.build_filename(directory, "fixture.sock");
            var listener = new SocketListener();
            SocketAddress bound;
            listener.add_address(new UnixSocketAddress(socket_path), SocketType.STREAM,
                SocketProtocol.DEFAULT, null, out bound);
            var peer = new Thread<void*>("media-qmp-fixture", () => {
                try {
                    var connection = listener.accept();
                    connection.socket.timeout = 1;
                    size_t written;
                    connection.output_stream.write_all("{\"QMP\":{}}\n".data, out written);
                    var input = new DataInputStream(connection.input_stream);
                    for (int i = 0; i < 2; i++) {
                        string? line = input.read_line();
                        assert(line != null);
                        var parser = new Json.Parser();
                        parser.load_from_data(line);
                        var request = parser.get_root().get_object();
                        string reply = "{\"id\":" + request.get_int_member("id").to_string() +
                            ",\"return\":" + (i == 0 ? "{}" : "[]") + "}\n";
                        connection.output_stream.write_all(reply.data, out written);
                    }
                    uint8[] buffer = new uint8[1];
                    // Successful QMP calls must promptly release their connection,
                    // rather than retain the client in the watchdog closure.
                    assert(connection.input_stream.read(buffer) == 0);
                    connection.close();
                } catch (Error e) { error("Private QMP fixture failed: %s", e.message); }
                return null;
            });
            var resource = new Resource();
            resource.kind = "qemu";
            resource.qmp_socket = socket_path;
            var result = new GuestMedia().qmp(resource, "query-block");
            assert(result.get_node_type() == Json.NodeType.ARRAY);
            peer.join();
            listener.close();
            FileUtils.unlink(socket_path);
        }

        public static void test_qmp_media() {
            string? dir = null;
            try {
                dir = DirUtils.make_tmp("rigs-media-test-XXXXXX");
                string iso = make_iso(dir);
                var resource = new Resource(); resource.kind = "qemu";
                var media = new FakeMedia();
                var drives = media.list_drives(resource);
                assert(drives.length == 2 && drives[0].id == "cd0");
                assert(drives[1].current_iso == "/occupied.iso");
                bool rejected = false;
                try { media.attach(resource, iso, "cd1"); } catch (IOError.EXISTS e) { rejected = true; }
                assert(rejected && media.arguments == null);
                media.attach(resource, iso, "cd0");
                assert(media.calls[media.calls.length - 1] == "blockdev-close-tray");
                assert(media.image.get_object_member("file").get_string_member("filename") == iso);
                assert(media.image.get_string_member("driver") == "raw");
                assert(media.image.get_boolean_member("read-only"));
                assert(media.arguments.get_string_member("id") == "cd0");
                assert(!media.opening.get_boolean_member("force"));
                assert(media.insertion.get_string_member("node-name") == media.image.get_string_member("node-name"));
                assert(media.image.get_string_member("node-name").length < 32);
                media.fail_on = "blockdev-insert-medium";
                rejected = false;
                try { media.attach(resource, iso, "cd0"); } catch (IOError.FAILED e) { rejected = true; }
                assert(rejected && media.calls[media.calls.length - 1] == "blockdev-del");
                media.fail_on = "blockdev-close-tray";
                rejected = false;
                try { media.attach(resource, iso, "cd0"); } catch (IOError.FAILED e) { rejected = true; }
                assert(rejected && media.calls[media.calls.length - 1] == "blockdev-close-tray");
                media.fail_on = "";
                media.blocks = "[{\"device\":\"\",\"qdev\":\"/machine/peripheral/cd0\",\"removable\":true,\"tray_open\":true}]";
                assert(media.list_drives(resource)[0].id == "/machine/peripheral/cd0");
                media.attach(resource, iso, "/machine/peripheral/cd0");
                assert(media.insertion.get_string_member("id") == "/machine/peripheral/cd0");
                media.blocks = "[{\"device\":\"cd0\",\"removable\":true,\"tray_open\":true,\"inserted\":{}}]";
                assert(media.list_drives(resource)[0].current_iso.length > 0);
                media.blocks = "[{\"device\":\"disk0\",\"removable\":false},{\"device\":\"floppy0\",\"removable\":true}]";
                rejected = false;
                try { media.list_drives(resource); } catch (IOError.NOT_FOUND e) { rejected = true; }
                assert(rejected);
                check_qmp_client(dir);
                FileUtils.unlink(iso);
            } catch (Error e) { error("Media test failed: %s", e.message); }
            if (dir != null) DirUtils.remove(dir);
        }

        public static void test_libvirt_media() {
            string? dir = null;
            try {
                dir = DirUtils.make_tmp("rigs-media-test-XXXXXX");
                string iso = make_iso(dir);
                var resource = new Resource(); resource.kind = "libvirt";
                resource.resource_id = "01234567-89ab-cdef-0123-456789abcdef";
                resource.connection_uri = "qemu:///session";
                var commands = new MediaCommands();
                var media = new GuestMedia(commands);
                var drives = media.list_drives(resource);
                assert(drives.length == 2 && drives[0].current_iso == "");
                assert(drives[1].current_iso == "/data/installer with spaces.iso");
                media.attach(resource, iso, "sda");
                string call = commands.calls[commands.calls.length - 1];
                assert(call == "virsh|--connect|qemu:///session|change-media|" + resource.resource_id + "|sda|" + iso + "|--insert|--live");
                assert(!call.contains("--force") && !call.contains("--config"));
                bool rejected = false;
                try { media.attach(resource, iso, "sdb"); } catch (IOError.EXISTS e) { rejected = true; }
                assert(rejected);
                FileUtils.unlink(iso);
            } catch (Error e) { error("Libvirt media test failed: %s", e.message); }
            if (dir != null) DirUtils.remove(dir);
        }

        public static void test_invalid_targets() {
            string? dir = null;
            try {
                dir = DirUtils.make_tmp("rigs-media-test-XXXXXX");
                string iso = make_iso(dir);
                var commands = new MediaCommands();
                var media = new FakeMedia(commands);
                var resource = new Resource(); resource.kind = "container";
                resource.resource_id = "0123456789abcdef"; resource.runtime = "/bin/bash";
                bool rejected = false;
                try { media.attach(resource, iso, "cd0"); } catch (IOError.INVALID_ARGUMENT e) { rejected = true; }
                assert(rejected && commands.calls.length == 0 && media.arguments == null);
                rejected = false;
                try { media.attach(resource, iso, "--all"); } catch (IOError.INVALID_ARGUMENT e) { rejected = true; }
                assert(rejected);
                resource.kind = "libvirt"; resource.connection_uri = "qemu+ssh://host/system";
                rejected = false;
                try { new GuestMedia(commands).list_drives(resource); } catch (IOError.INVALID_ARGUMENT e) { rejected = true; }
                assert(rejected && commands.calls.length == 0);
                resource.kind = "qemu";
                rejected = false;
                try { new GuestMedia(commands).list_drives(resource); } catch (IOError.NOT_CONNECTED e) { rejected = true; }
                assert(rejected);
                FileUtils.unlink(iso);
            } catch (Error e) { error("Invalid media target test failed: %s", e.message); }
            if (dir != null) DirUtils.remove(dir);
        }

        public static void test_container_mounts() {
            string? dir = null;
            try {
                dir = DirUtils.make_tmp("rigs-media-test-XXXXXX");
                string iso = make_iso(dir);
                var resource = new Resource(); resource.kind = "container"; resource.runtime = "podman";
                resource.resource_id = "0123456789abcdef";
                var commands = new MediaCommands();
                var media = new FakeMedia(commands);
                var mounts = new Json.Array();
                var mount = new Json.Object();
                mount.set_string_member("Source", dir); mount.set_string_member("Destination", "/images");
                mount.set_boolean_member("RW", false); mounts.add_object_element(mount);
                var root = new Json.Node(Json.NodeType.ARRAY); root.set_array(mounts);
                var generator = new Json.Generator(); generator.set_root(root); commands.mounts = generator.to_data(null);
                media.attach(resource, iso, "cd0");
                assert(media.image.get_object_member("file").get_string_member("filename") == "/images/driver image.iso");
                commands.mounts = "[]";
                bool rejected = false;
                try { media.attach(resource, iso, "cd0"); } catch (IOError.NOT_SUPPORTED e) { rejected = true; }
                assert(rejected);
                string storage = Path.build_filename(dir, "storage");
                assert(DirUtils.create(storage, 0700) == 0);
                mount.set_string_member("Source", storage);
                mount.set_string_member("Destination", "/storage");
                mount.set_boolean_member("RW", true);
                commands.mounts = generator.to_data(null);
                media.attach(resource, iso, "cd0");
                string staged_guest = media.image.get_object_member("file").get_string_member("filename");
                assert(staged_guest.has_prefix("/storage/.rigs-media/") && staged_guest.has_suffix(".iso"));
                string staged_host = storage + staged_guest.substring("/storage".length);
                GuestMedia.validate_iso(staged_host);
                media.attach(resource, iso, "cd0");
                assert(media.image.get_object_member("file").get_string_member("filename") == staged_guest);
                FileUtils.set_contents(staged_host, "do not overwrite");
                rejected = false;
                try { media.attach(resource, iso, "cd0"); } catch (IOError.EXISTS e) { rejected = true; }
                assert(rejected);
                string untouched;
                FileUtils.get_contents(staged_host, out untouched);
                assert(untouched == "do not overwrite");
                FileUtils.unlink(staged_host);
                DirUtils.remove(Path.build_filename(storage, ".rigs-media"));
                DirUtils.remove(storage);
                FileUtils.unlink(iso);
            } catch (Error e) { error("Container media test failed: %s", e.message); }
            if (dir != null) DirUtils.remove(dir);
        }

        public static void test_iso_validation() {
            string? dir = null;
            try {
                dir = DirUtils.make_tmp("rigs-media-test-XXXXXX");
                string iso = make_iso(dir);
                GuestMedia.validate_iso(iso);
                FileUtils.set_contents(iso, "not an ISO");
                bool rejected = false;
                try { GuestMedia.validate_iso(iso); } catch (IOError.INVALID_DATA e) { rejected = true; }
                assert(rejected);
                FileUtils.unlink(iso);
            } catch (Error e) { error("ISO validation test failed: %s", e.message); }
            if (dir != null) DirUtils.remove(dir);
        }
    }
}
