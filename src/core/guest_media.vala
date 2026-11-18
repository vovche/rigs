namespace Rigs {
    public class GuestOpticalDrive : Object {
        public string id;
        public string current_iso;
        public GuestOpticalDrive(string id, string current_iso = "") {
            this.id = id;
            this.current_iso = current_iso;
        }
    }

    public class GuestMedia : Object {
        private HostCommand commands;
        public GuestMedia(HostCommand? commands = null) {
            this.commands = commands ?? new HostCommand();
        }

        private class Client : Object {
            private class DeadlineState : Object {
                public Mutex mutex = Mutex();
                public Cond cond = Cond();
                public bool finished = false;
            }
            private SocketConnection connection;
            private DataInputStream input;
            private int64 deadline;
            private int sequence = 0;
            private Cancellable cancellable = new Cancellable();
            private DeadlineState deadline_state = new DeadlineState();
            private Thread<void*>? watchdog;

            public Client(string path) throws Error {
                deadline = get_monotonic_time() + 3000000;
                watchdog = start_watchdog(deadline_state, cancellable, deadline);
                var socket_client = new SocketClient();
                socket_client.timeout = 1;
                connection = socket_client.connect(new UnixSocketAddress(path), cancellable);
                connection.socket.timeout = 1;
                input = new DataInputStream(connection.input_stream);
                if (!receive().has_member("QMP")) throw new IOError.INVALID_DATA("Missing QMP greeting.");
                command("qmp_capabilities");
            }

            // A constructor lambda retains the Client, potentially finalizing it
            // on its own watchdog thread. This static closure owns only its state.
            private static Thread<void*> start_watchdog(DeadlineState state, Cancellable cancellation, int64 expires) {
                return new Thread<void*>("media-qmp-deadline", () => {
                    state.mutex.lock();
                    while (!state.finished) {
                        if (!state.cond.wait_until(state.mutex, expires) && !state.finished) {
                            cancellation.cancel();
                            break;
                        }
                    }
                    state.mutex.unlock();
                    return null;
                });
            }

            ~Client() {
                deadline_state.mutex.lock();
                deadline_state.finished = true;
                deadline_state.cond.signal();
                deadline_state.mutex.unlock();
                if (watchdog != null) watchdog.join();
                if (connection != null) {
                    try { connection.close(); } catch (Error e) { }
                }
            }

            private Json.Object receive() throws Error {
                var line = new StringBuilder();
                while (line.len < 1048576) {
                    if (get_monotonic_time() >= deadline) throw new IOError.TIMED_OUT("QMP operation timed out.");
                    uint8 c;
                    try { c = input.read_byte(cancellable); }
                    catch (IOError.CANCELLED e) { throw new IOError.TIMED_OUT("QMP operation timed out."); }
                    if (c == '\n') {
                        var parser = new Json.Parser();
                        parser.load_from_data(line.str);
                        var root = parser.get_root();
                        if (root == null || root.get_node_type() != Json.NodeType.OBJECT)
                            throw new IOError.INVALID_DATA("Invalid QMP response.");
                        return root.get_object();
                    }
                    line.append_c((char)c);
                }
                throw new IOError.INVALID_DATA("QMP response exceeds 1 MiB.");
            }

            public Json.Node command(string name, Json.Object? args = null) throws Error {
                if (get_monotonic_time() >= deadline) throw new IOError.TIMED_OUT("QMP operation timed out.");
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
                try { connection.output_stream.write_all(payload.data, out written, cancellable); }
                catch (IOError.CANCELLED e) { throw new IOError.TIMED_OUT("QMP operation timed out."); }
                for (int i = 0; i < 64; i++) {
                    var response = receive();
                    if (response.has_member("event")) continue;
                    if (!response.has_member("id") || response.get_member("id").get_value_type() != typeof(int64) ||
                        response.get_int_member("id") != id) continue;
                    if (response.has_member("error")) {
                        string detail = "QMP rejected the media operation.";
                        var error = response.get_member("error");
                        if (error.get_node_type() == Json.NodeType.OBJECT)
                            detail = text(error.get_object(), "desc") ?? detail;
                        throw new IOError.FAILED("%s", detail);
                    }
                    if (!response.has_member("return")) throw new IOError.INVALID_DATA("Missing QMP result.");
                    return response.get_member("return").copy();
                }
                throw new IOError.INVALID_DATA("No matching QMP response.");
            }
        }

        private static string? text(Json.Object obj, string key) {
            if (!obj.has_member(key)) return null;
            var node = obj.get_member(key);
            return node.get_node_type() == Json.NodeType.VALUE && node.get_value_type() == typeof(string)
                ? node.get_string() : null;
        }

        private static void validate_libvirt(Resource resource) throws Error {
            if ((resource.connection_uri != "qemu:///session" && resource.connection_uri != "qemu:///system") ||
                !Regex.match_simple("^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$", resource.resource_id))
                throw new IOError.INVALID_ARGUMENT("Choose a local libvirt connection and valid domain UUID.");
        }

        public virtual Json.Node qmp(Resource resource, string name, Json.Object? args = null) throws Error {
            if (!resource.qmp_socket.has_prefix("/"))
                throw new IOError.NOT_CONNECTED("Configure the host QMP socket path before attaching an ISO.");
            if (resource.kind != "qemu" && resource.kind != "compose" && resource.kind != "container")
                throw new IOError.NOT_SUPPORTED("This resource does not provide a supported QMP connection.");
            return new Client(resource.qmp_socket).command(name, args);
        }

        public virtual GenericArray<GuestOpticalDrive> list_drives(Resource resource) throws Error {
            var drives = new GenericArray<GuestOpticalDrive>();
            if (resource.kind == "libvirt") {
                validate_libvirt(resource);
                var result = commands.run({ "virsh", "--connect", resource.connection_uri, "domblklist", resource.resource_id, "--details" });
                if (result.exit_status != 0) throw new IOError.FAILED("Cannot list CD drives: %s", result.error_output);
                foreach (string line in result.output.split("\n")) {
                    // Keep the complete source column, including paths containing spaces.
                    var pattern = new Regex("^\\s*(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(.+?)\\s*$");
                    MatchInfo info;
                    if (!pattern.match(line, 0, out info) || info.fetch(2) != "cdrom") continue;
                    string id = info.fetch(3);
                    if (!valid_drive(id)) continue;
                    string source = info.fetch(4);
                    drives.add(new GuestOpticalDrive(id, source == "-" ? "" : source));
                }
            } else {
                var response = qmp(resource, "query-block");
                if (response.get_node_type() != Json.NodeType.ARRAY) throw new IOError.INVALID_DATA("Invalid QMP block device list.");
                var blocks = response.get_array();
                for (uint i = 0; i < blocks.get_length(); i++) {
                    var entry = blocks.get_element(i);
                    if (entry.get_node_type() != Json.NodeType.OBJECT) continue;
                    var obj = entry.get_object();
                    if (!obj.has_member("removable") || obj.get_member("removable").get_value_type() != typeof(bool) ||
                        !obj.get_boolean_member("removable") || !obj.has_member("tray_open") ||
                        obj.get_member("tray_open").get_value_type() != typeof(bool)) continue;
                    // Medium insertion requires the guest device's QOM identity,
                    // rather than the block backend name returned as "device".
                    string? id = text(obj, "qdev") ?? text(obj, "device");
                    if (id != null && id.length == 0) id = text(obj, "device");
                    if (id == null || !valid_drive(id)) continue;
                    string current = "";
                    if (obj.has_member("inserted")) {
                        // Any inserted medium is occupied, even if its name is unavailable.
                        current = "(occupied)";
                        var inserted = obj.get_member("inserted");
                        if (inserted.get_node_type() == Json.NodeType.OBJECT)
                            current = text(inserted.get_object(), "file") ?? current;
                        if (current.length == 0) current = "(occupied)";
                    }
                    drives.add(new GuestOpticalDrive(id, current));
                }
            }
            if (drives.length == 0) throw new IOError.NOT_FOUND("No CD-ROM drive was found. Add an optical drive in your VM manager first.");
            return drives;
        }

        private static bool valid_drive(string id) {
            return Regex.match_simple("^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$", id) ||
                Regex.match_simple("^/machine/[A-Za-z0-9_./\\[\\]:-]{1,511}$", id);
        }

        public static void validate_iso(string path) throws Error {
            if (!path.has_prefix("/") || !path.down().has_suffix(".iso"))
                throw new IOError.INVALID_ARGUMENT("Choose an absolute path to an ISO file.");
            var file = File.new_for_path(path);
            var info = file.query_info("standard::type,access::can-read", FileQueryInfoFlags.NONE);
            if (info.get_file_type() != FileType.REGULAR || !info.get_attribute_boolean("access::can-read"))
                throw new IOError.PERMISSION_DENIED("The ISO must be a readable regular file.");
            var stream = file.read();
            stream.seek(32769, SeekType.SET);
            uint8[] signature = new uint8[5];
            size_t count;
            stream.read_all(signature, out count);
            stream.close();
            if (count != 5 || signature[0] != 'C' || signature[1] != 'D' || signature[2] != '0' || signature[3] != '0' || signature[4] != '1')
                throw new IOError.INVALID_DATA("The file does not contain an ISO9660 CD001 descriptor.");
        }

        private string container_iso(Resource resource, string iso_path) throws Error {
            if (resource.runtime != "podman" && resource.runtime != "docker")
                throw new IOError.INVALID_ARGUMENT("Only Podman or Docker containers are supported.");
            string identity = resource.kind == "container" ? resource.resource_id : resource.container_name;
            bool valid = resource.kind == "container"
                ? Regex.match_simple("^[a-fA-F0-9]{12,64}$", identity)
                : Regex.match_simple("^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$", identity);
            if (!valid) throw new IOError.INVALID_ARGUMENT("The container identity is missing or invalid.");
            var inspected = commands.run({ resource.runtime, "inspect", "--format", "{{json .Mounts}}", identity });
            if (inspected.exit_status != 0) throw new IOError.FAILED("Cannot inspect container mounts: %s", inspected.error_output);
            var parser = new Json.Parser();
            parser.load_from_data(inspected.output);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.ARRAY) throw new IOError.INVALID_DATA("Invalid container mount list.");
            string source_path = Filename.canonicalize(iso_path);
            string? mapped = null;
            int best_length = -1;
            string? storage = null;
            var mounts = root.get_array();
            for (uint i = 0; i < mounts.get_length(); i++) {
                var entry = mounts.get_element(i);
                if (entry.get_node_type() != Json.NodeType.OBJECT) continue;
                var obj = entry.get_object();
                string? source = text(obj, "Source");
                string? destination = text(obj, "Destination");
                if (source == null || destination == null || !source.has_prefix("/") || !destination.has_prefix("/")) continue;
                source = Filename.canonicalize(source);
                destination = Filename.canonicalize(destination);
                if ((source_path == source || source_path.has_prefix(source == "/" ? "/" : source + "/")) && source.length > best_length) {
                    mapped = destination + source_path.substring(source == "/" ? 0 : source.length);
                    best_length = source.length;
                }
                if (destination == "/storage" && obj.has_member("RW") &&
                    obj.get_member("RW").get_value_type() == typeof(bool) && obj.get_boolean_member("RW")) storage = source;
            }
            if (mapped != null) return mapped;
            if (storage == null) throw new IOError.NOT_SUPPORTED("The ISO is outside container mounts. Add a writable /storage mount or choose an ISO already inside a mounted directory.");
            return stage_iso(source_path, storage);
        }

        private static string digest(File file) throws Error {
            var checksum = new Checksum(ChecksumType.SHA256);
            var input = file.read();
            uint8[] buffer = new uint8[65536];
            ssize_t count;
            while ((count = input.read(buffer)) > 0) checksum.update(buffer[0:(int)count], (size_t)count);
            input.close();
            return checksum.get_string();
        }

        private static string stage_iso(string iso_path, string storage) throws Error {
            string staging_path = Path.build_filename(storage, ".rigs-media");
            if (!FileUtils.test(staging_path, FileTest.EXISTS)) {
                if (DirUtils.create(staging_path, 0700) != 0)
                    throw new IOError.PERMISSION_DENIED("Cannot create the private ISO staging directory in /storage.");
            }
            var staging = File.new_for_path(staging_path);
            var info = staging.query_info("standard::type,unix::mode,owner::user", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
            if (info.get_file_type() != FileType.DIRECTORY || (info.get_attribute_uint32("unix::mode") & 0077) != 0 ||
                info.get_attribute_string("owner::user") != Environment.get_user_name())
                throw new IOError.PERMISSION_DENIED("The .rigs-media directory must be owned by you with owner-only permissions.");
            var source = File.new_for_path(iso_path);
            string hash = digest(source);
            string name = hash + ".iso";
            var destination = staging.get_child(name);
            if (destination.query_exists()) {
                var existing = destination.query_info("standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                if (existing.get_file_type() != FileType.REGULAR || digest(destination) != hash)
                    throw new IOError.EXISTS("The ISO staging path is already occupied by another file.");
                return "/storage/.rigs-media/" + name;
            }
            var temporary = staging.get_child(".partial-" + Uuid.string_random());
            try {
                source.copy(temporary, FileCopyFlags.NONE);
                temporary.set_attribute_uint32("unix::mode", 0600, FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                if (digest(temporary) != hash) throw new IOError.INVALID_DATA("The ISO changed while it was being staged. Try again.");
                temporary.move(destination, FileCopyFlags.NONE);
            } catch (Error e) {
                try { temporary.delete(); } catch (Error ignored) { }
                throw e;
            }
            return "/storage/.rigs-media/" + name;
        }

        public virtual void attach(Resource resource, string iso_path, string drive_id) throws Error {
            if (!valid_drive(drive_id)) throw new IOError.INVALID_ARGUMENT("Invalid optical drive identity.");
            validate_iso(iso_path);
            // Re-read immediately before mutation: never deliberately replace existing media.
            var drives = list_drives(resource);
            GuestOpticalDrive? selected = null;
            foreach (var drive in drives.data) if (drive.id == drive_id) selected = drive;
            if (selected == null) throw new IOError.NOT_FOUND("The selected CD-ROM drive is no longer available.");
            if (selected.current_iso.length > 0) throw new IOError.EXISTS("The selected CD-ROM drive already contains media. Eject it in your VM manager first.");
            string guest_path = iso_path;
            if (resource.kind == "compose" || resource.kind == "container") guest_path = container_iso(resource, iso_path);
            // Staging a large image may take time; check the tray again afterwards.
            if (resource.kind == "compose" || resource.kind == "container") {
                bool found_empty = false;
                foreach (var drive in list_drives(resource).data) {
                    if (drive.id != drive_id) continue;
                    if (drive.current_iso.length > 0) throw new IOError.EXISTS("The CD-ROM drive became occupied while preparing the ISO. No media was replaced.");
                    found_empty = true;
                }
                if (!found_empty) throw new IOError.NOT_FOUND("The selected CD-ROM drive is no longer available.");
            }
            if (resource.kind == "libvirt") {
                var result = commands.run({ "virsh", "--connect", resource.connection_uri, "change-media", resource.resource_id,
                    drive_id, guest_path, "--insert", "--live" });
                if (result.exit_status != 0) throw new IOError.FAILED("Cannot attach the ISO: %s", result.error_output);
            } else {
                string node_name = "rigs-" + Uuid.string_random().replace("-", "").substring(0, 24);
                var file = new Json.Object();
                file.set_string_member("driver", "file");
                file.set_string_member("filename", guest_path);
                var image = new Json.Object();
                image.set_string_member("driver", "raw");
                image.set_string_member("node-name", node_name);
                image.set_boolean_member("read-only", true);
                image.set_object_member("file", file);
                qmp(resource, "blockdev-add", image);
                try {
                    var open = new Json.Object();
                    open.set_string_member("id", drive_id);
                    open.set_boolean_member("force", false);
                    qmp(resource, "blockdev-open-tray", open);
                    var insert = new Json.Object();
                    insert.set_string_member("id", drive_id);
                    insert.set_string_member("node-name", node_name);
                    // Unlike change-medium, insert-medium fails if media is present.
                    qmp(resource, "blockdev-insert-medium", insert);
                } catch (Error e) {
                    var cleanup = new Json.Object();
                    cleanup.set_string_member("node-name", node_name);
                    try { qmp(resource, "blockdev-del", cleanup); } catch (Error ignored) { }
                    throw e;
                }
                // Once inserted, retain the medium even if closing its tray fails.
                var close = new Json.Object();
                close.set_string_member("id", drive_id);
                qmp(resource, "blockdev-close-tray", close);
            }
        }
    }
}
