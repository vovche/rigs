using GLib.Intl;

/* resource_presets.vala — ready-made settings for a new resource, read from its folder.
 *
 * compose.yaml  → kind COMPOSE, container_name, guest_os (dockur/windows image), ports summary
 * run-vm.sh     → kind QEMU, process_match (-name … process=…), monitor/QMP/guest-agent sockets,
 *                 connect command from -spice (unix socket or port), simple $VAR expansion
 *
 * Parsing is deliberately shallow (no YAML or shell interpreter): anything not recognized is
 * left empty for the user to fill in. validate() is what the Add button checks. */
namespace Rigs {
    public class ResourcePresets : Object {
        public const string[] COMPOSE_FILES = { "compose.yaml", "compose.yml", "docker-compose.yml", "docker-compose.yaml" };
        public const string QEMU_SCRIPT = "run-vm.sh";
        private const int MAX_FILE = 256 * 1024;
        private const int MAX_PORTS = 4;

        public static string icon_for(ResourceKind kind) {
            switch (kind) {
                case ResourceKind.QEMU: case ResourceKind.LIBVIRT: return "computer-symbolic";
                default: return "network-server-symbolic";
            }
        }

        public static Resource blank(ResourceKind kind, string dir = "") {
            var resource = new Resource();
            resource.id = Uuid.string_random();
            resource.kind = kind;
            resource.icon = icon_for(kind);
            resource.dir = dir;
            resource.name = dir.length > 0 ? Path.get_basename(dir) : "";
            return resource;
        }

        public static string? find_compose_file(string dir) {
            foreach (string name in COMPOSE_FILES) {
                string path = Path.build_filename(dir, name);
                if (FileUtils.test(path, FileTest.IS_REGULAR)) return path;
            }
            return null;
        }

        // Folder → best guess. Unknown folders become a blank compose resource for that directory.
        public static Resource for_folder(string dir, ContainerRuntime runtime = ContainerRuntime.PODMAN) {
            string? compose = find_compose_file(dir);
            if (compose != null) return from_compose(dir, read_small(compose), runtime);
            string script = Path.build_filename(dir, QEMU_SCRIPT);
            if (FileUtils.test(script, FileTest.IS_REGULAR)) return from_qemu_script(dir, read_small(script));
            var resource = blank(ResourceKind.COMPOSE, dir);
            resource.runtime = runtime;
            return resource;
        }

        private static string read_small(string path) {
            try {
                uint8[] data;
                FileUtils.get_data(path, out data);
                int length = int.min(data.length, MAX_FILE);
                return HostCommand.bytes_to_text(new Bytes(data[0:length]));
            } catch (Error e) {
                return "";
            }
        }

        // ---- compose.yaml ------------------------------------------------------------------

        public static Resource from_compose(string dir, string text, ContainerRuntime runtime = ContainerRuntime.PODMAN) {
            var resource = blank(ResourceKind.COMPOSE, dir);
            resource.runtime = runtime;
            var ports = new GenericArray<string>();
            var seen = new HashTable<string, bool>(str_hash, str_equal);
            foreach (string raw in text.split("\n")) {
                string comment = "";
                string line = raw;
                int hash = raw.index_of(" #");
                if (hash >= 0) { comment = raw.substring(hash + 2).strip(); line = raw.substring(0, hash); }
                string trimmed = line.strip();
                if (resource.container_name.length == 0 && trimmed.has_prefix("container_name:"))
                    resource.container_name = unquote(trimmed.substring("container_name:".length).strip());
                else if (trimmed.has_prefix("image:")) {
                    string image = unquote(trimmed.substring("image:".length).strip());
                    if (image.contains("dockur/windows") || image.contains("dockurr/windows")) resource.guest_os = "windows";
                } else if (trimmed.has_prefix("- ")) {
                    string host_port = compose_host_port(unquote(trimmed.substring(2).strip()));
                    if (host_port.length > 0 && !seen.contains(host_port) && ports.length < MAX_PORTS) {
                        seen.insert(host_port, true);
                        string[] comment_parts = comment.split("(");
                        string label = comment_parts.length > 0 ? comment_parts[0].strip() : "";
                        ports.add(label.length > 0 ? "%s :%s".printf(label, host_port) : ":" + host_port);
                    }
                }
            }
            resource.details = string.joinv(" • ", ports.data);
            if (resource.guest_os == "windows") resource.subtitle = _("Windows • Compose");
            else resource.subtitle = _("Compose project");
            return resource;
        }

        // "8007:8006", "127.0.0.1:3390:3389/udp" → host port; anything else (volumes, env) → "".
        public static string compose_host_port(string mapping) {
            string[] protocol_parts = mapping.split("/");
            string value = protocol_parts.length > 0 ? protocol_parts[0] : "";
            string[] parts = value.split(":");
            if (parts.length < 2) return "";
            string host = parts[parts.length - 2];
            int port;
            if (!int.try_parse(host, out port) || port <= 0 || port > 65535) return "";
            if (!int.try_parse(parts[parts.length - 1], out port)) return "";
            return host;
        }

        private static string unquote(string value) {
            string v = value.strip();
            if (v.length >= 2 && ((v.has_prefix("\"") && v.has_suffix("\"")) || (v.has_prefix("'") && v.has_suffix("'"))))
                return v.substring(1, v.length - 2);
            return v;
        }

        // ---- run-vm.sh ---------------------------------------------------------------------

        public static Resource from_qemu_script(string dir, string text) {
            var resource = blank(ResourceKind.QEMU, dir);
            resource.start_cmd = "./" + QEMU_SCRIPT;
            resource.subtitle = _("QEMU script");
            string[] tokens = qemu_tokens(text);
            string? agent_chardev = null;
            var chardev_paths = new HashTable<string, string>(str_hash, str_equal);
            string? spice = null;
            for (int i = 0; i + 1 < tokens.length; i++) {
                string option = tokens[i];
                string value = tokens[i + 1];
                switch (option) {
                    case "-name":
                        string[] name_parts = value.split(",");
                        string? process = suboption(value, "process");
                        string first_name = name_parts.length > 0 ? name_parts[0] : "";
                        resource.process_match = process != null ? process : first_name;
                        if (resource.name.length == 0) resource.name = first_name;
                        break;
                    case "-monitor":
                        resource.monitor_socket = unix_path(value) ?? resource.monitor_socket;
                        break;
                    case "-qmp":
                        resource.qmp_socket = unix_path(value) ?? resource.qmp_socket;
                        break;
                    case "-spice":
                        spice = value;
                        break;
                    case "-chardev":
                        string? id = suboption(value, "id");
                        string? path = suboption(value, "path");
                        if (value.has_prefix("socket,") && id != null && path != null) chardev_paths.insert(id, path);
                        break;
                    case "-device":
                        if (value.has_prefix("virtserialport,") && suboption(value, "name") == "org.qemu.guest_agent.0")
                            agent_chardev = suboption(value, "chardev");
                        break;
                }
            }
            if (agent_chardev != null && chardev_paths.contains(agent_chardev))
                resource.guest_agent_socket = chardev_paths.lookup(agent_chardev);
            if (spice != null) {
                string? addr = suboption(spice, "addr");
                string? port = suboption(spice, "port");
                if (suboption(spice, "unix") == "on" && addr != null)
                    resource.connect_cmd = "remote-viewer spice+unix://" + addr;
                else if (port != null)
                    resource.connect_cmd = "remote-viewer spice://127.0.0.1:" + port;
            }
            return resource;
        }

        // Joins "\"-continued lines, expands literal VAR=value assignments, drops quotes, splits on blanks.
        public static string[] qemu_tokens(string script) {
            var vars = new HashTable<string, string>(str_hash, str_equal);
            var joined = new StringBuilder();
            foreach (string raw in script.replace("\\\n", " ").split("\n")) {
                string line = raw.strip();
                if (line.has_prefix("#")) continue;
                MatchInfo info;
                try {
                    if (new Regex("^(?:export\\s+)?([A-Za-z_][A-Za-z0-9_]*)=(\"[^\"$`]*\"|'[^']*'|[^\\s\"'$`;]*)\\s*$").match(line, 0, out info)) {
                        vars.insert(info.fetch(1), unquote(info.fetch(2)));
                        continue;
                    }
                } catch (RegexError e) { }
                joined.append(line).append_c(' ');
            }
            string text = joined.str;
            try {
                text = new Regex("\\$\\{([A-Za-z_][A-Za-z0-9_]*)\\}|\\$([A-Za-z_][A-Za-z0-9_]*)").replace_eval(text, -1, 0, 0, (info, result) => {
                    string name = info.fetch(1);
                    if (name == null || name.length == 0) name = info.fetch(2);
                    result.append(vars.lookup(name) ?? "");
                    return false;
                });
            } catch (RegexError e) { }
            text = text.replace("\"", "").replace("'", "");
            string[] tokens = {};
            foreach (string token in Regex.split_simple("\\s+", text)) if (token.length > 0) tokens += token;
            return tokens;
        }

        // "a,key=value,b" → "value"; null when absent.
        public static string? suboption(string value, string key) {
            foreach (string part in value.split(",")) {
                if (part.has_prefix(key + "=")) return part.substring(key.length + 1);
            }
            return null;
        }

        // "unix:/tmp/x.sock,server=on" or "unix:path=/tmp/x.sock" → "/tmp/x.sock".
        public static string? unix_path(string value) {
            if (!value.has_prefix("unix:")) return null;
            string[] parts = value.substring(5).split(",");
            string first = parts.length > 0 ? parts[0] : "";
            if (first.has_prefix("path=")) first = first.substring(5);
            return first.length > 0 ? first : null;
        }

        // ---- validation -------------------------------------------------------------------

        // null when the resource can be added; otherwise one sentence telling the user what to fix.
        public static string? validate(Resource resource) {
            if (resource.name.strip().length == 0) return _("Enter a name.");
            switch (resource.kind) {
                case ResourceKind.COMPOSE:
                    if (!FileUtils.test(resource.dir, FileTest.IS_DIR)) return _("Choose the project folder.");
                    if (resource.start_cmd.length == 0 && find_compose_file(resource.dir) == null)
                        return _("The folder has no compose.yaml; enter a start command.");
                    if (resource.container_name.length > 0 &&
                        !Regex.match_simple("^[A-Za-z0-9][A-Za-z0-9_.-]*$", resource.container_name))
                        return _("The container name may contain only letters, digits, “_”, “.” and “-”.");
                    break;
                case ResourceKind.QEMU:
                    if (!FileUtils.test(resource.dir, FileTest.IS_DIR)) return _("Choose the VM folder.");
                    if (resource.start_cmd.length == 0 &&
                        !FileUtils.test(Path.build_filename(resource.dir, QEMU_SCRIPT), FileTest.IS_REGULAR))
                        return _("The folder has no run-vm.sh; enter a start command.");
                    break;
                case ResourceKind.CONTAINER:
                    if (!ContainerDriver.valid_target(resource)) return _("The container ID is not valid.");
                    break;
                case ResourceKind.LIBVIRT:
                    if (!LibvirtDriver.valid_target(resource)) return _("The libvirt domain is not valid.");
                    break;
            }
            // "./script args" must name a file in the folder (the command runs there).
            string[] words = resource.start_cmd.split(" ");
            string script = words.length > 0 ? words[0] : "";
            if (script.has_prefix("./") && FileUtils.test(resource.dir, FileTest.IS_DIR) &&
                !FileUtils.test(Path.build_filename(resource.dir, script.substring(2)), FileTest.IS_REGULAR))
                return _("%s does not exist in the folder.").printf(script);
            foreach (string socket in new string[] { resource.monitor_socket, resource.qmp_socket, resource.guest_agent_socket }) {
                if (socket.length > 0 && !Path.is_absolute(socket)) return _("Socket paths must be absolute.");
            }
            return null;
        }
    }
}
