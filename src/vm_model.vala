using GLib.Intl;

/* vm_model.vala — VM data models and configuration management for Rigs */

namespace Rigs {

    public class VmModel : Object {
        public string id { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string subtitle { get; set; default = ""; }
        public string vm_type { get; set; default = "compose"; }
        public string icon { get; set; default = "computer-symbolic"; }
        public string dir { get; set; default = ""; }
        public string start_cmd { get; set; default = ""; }
        public string stop_cmd { get; set; default = ""; }
        public string connect_cmd { get; set; default = ""; }
        public string details { get; set; default = ""; }
        public string container_name { get; set; default = ""; }
        public string process_name { get; set; default = ""; }
        public string monitor_socket { get; set; default = ""; }
        public string attached_iso { get; set; default = ""; }
        public string qmp_socket { get; set; default = ""; }
        public string guest_agent_socket { get; set; default = ""; }
        public string guest_os { get; set; default = ""; }
        public string runtime { get; set; default = "podman"; }
        public string resource_id { get; set; default = ""; }
        public string connection_uri { get; set; default = "qemu:///session"; }

        // Runtime-only (never persisted): outcome of the most recent failed start.
        public StartupIssue? last_startup_issue { get; set; default = null; }
        public signal void startup_failed(StartupIssue issue);

        public static VmModel from_json_node(Json.Node node) {
            var model = new VmModel();
            if (node.get_node_type() != Json.NodeType.OBJECT) {
                return model;
            }
            unowned Json.Object obj = node.get_object();

            if (obj.has_member("id")) model.id = obj.get_string_member("id");
            if (obj.has_member("name")) model.name = obj.get_string_member("name");
            if (obj.has_member("subtitle")) model.subtitle = obj.get_string_member("subtitle");
            if (obj.has_member("type")) model.vm_type = obj.get_string_member("type");
            if (obj.has_member("icon")) model.icon = obj.get_string_member("icon");
            if (obj.has_member("dir")) model.dir = obj.get_string_member("dir");
            if (obj.has_member("start_cmd")) model.start_cmd = obj.get_string_member("start_cmd");
            if (obj.has_member("stop_cmd")) model.stop_cmd = obj.get_string_member("stop_cmd");
            if (obj.has_member("connect_cmd")) model.connect_cmd = obj.get_string_member("connect_cmd");
            if (obj.has_member("details")) model.details = obj.get_string_member("details");
            if (obj.has_member("container_name")) model.container_name = obj.get_string_member("container_name");
            if (obj.has_member("process_name")) model.process_name = obj.get_string_member("process_name");
            if (obj.has_member("monitor_socket")) model.monitor_socket = obj.get_string_member("monitor_socket");
            if (obj.has_member("attached_iso")) model.attached_iso = obj.get_string_member("attached_iso");
            if (obj.has_member("qmp_socket")) model.qmp_socket = obj.get_string_member("qmp_socket");
            if (obj.has_member("guest_agent_socket")) model.guest_agent_socket = obj.get_string_member("guest_agent_socket");
            if (obj.has_member("guest_os")) model.guest_os = obj.get_string_member("guest_os");

            if (obj.has_member("runtime")) model.runtime = obj.get_string_member("runtime");
            if (obj.has_member("resource_id")) model.resource_id = obj.get_string_member("resource_id");
            if (obj.has_member("connection_uri")) model.connection_uri = obj.get_string_member("connection_uri");
            return model;
        }

        public Json.Object to_json_object() {
            var obj = new Json.Object();
            obj.set_string_member("id", id);
            obj.set_string_member("name", name);
            obj.set_string_member("subtitle", subtitle);
            obj.set_string_member("type", vm_type);
            obj.set_string_member("icon", icon);
            obj.set_string_member("dir", dir);
            obj.set_string_member("start_cmd", start_cmd);
            obj.set_string_member("stop_cmd", stop_cmd);
            obj.set_string_member("connect_cmd", connect_cmd);
            obj.set_string_member("details", details);
            if (container_name.length > 0) obj.set_string_member("container_name", container_name);
            if (process_name.length > 0) obj.set_string_member("process_name", process_name);
            if (monitor_socket.length > 0) obj.set_string_member("monitor_socket", monitor_socket);
            if (attached_iso.length > 0) obj.set_string_member("attached_iso", attached_iso);
            if (qmp_socket.length > 0) obj.set_string_member("qmp_socket", qmp_socket);
            if (guest_agent_socket.length > 0) obj.set_string_member("guest_agent_socket", guest_agent_socket);
            if (guest_os.length > 0) obj.set_string_member("guest_os", guest_os);
            obj.set_string_member("runtime", runtime);
            if (resource_id.length > 0) obj.set_string_member("resource_id", resource_id);
            if (vm_type == "libvirt") obj.set_string_member("connection_uri", connection_uri);
            return obj;
        }
    }

    public struct VmStatus {
        public bool running;
        public bool status_available;
        public double cpu_pct;
        public string ram_str;
        public double ram_pct;
        public bool guest_ram_valid;
        public string guest_ram_str;
        public double guest_ram_pct;
        public GuestMemoryState guest_memory_state;
    }

    public struct HostStatus {
        public double cpu_pct;
        public double ram_used_gb;
        public double ram_total_gb;
        public double ram_pct;
    }

    public class ConfigManager : Object {
        // QEMU-style sizes: "4096", "4G", "4GiB", "512M", "2T". Unknown input → 0.
        public static double parse_mem_to_mb(string raw) {
            string s = raw.strip().up();
            string[,] units = {
                { "TIB", "1048576" }, { "TB", "1048576" }, { "T", "1048576" },
                { "GIB", "1024" }, { "GB", "1024" }, { "G", "1024" },
                { "MIB", "1" }, { "MB", "1" }, { "M", "1" },
                { "KIB", "0.0009765625" }, { "KB", "0.0009765625" }, { "K", "0.0009765625" }
            };
            double factor = 1.0;
            for (int i = 0; i < units.length[0]; i++) {
                if (s.has_suffix(units[i, 0])) {
                    s = s.substring(0, s.length - units[i, 0].length).strip();
                    factor = double.parse(units[i, 1]);
                    break;
                }
            }
            double value = 0.0;
            if (s.length == 0 || !double.try_parse(s, out value) || value < 0) return 0.0;
            return value * factor;
        }

        public static string get_config_dir() {
            return Path.build_filename(Environment.get_user_config_dir(), "rigs");
        }

        public static string get_vms_file() {
            return Path.build_filename(get_config_dir(), "vms.json");
        }

        public static string get_state_file() {
            return Path.build_filename(get_config_dir(), "state.json");
        }

        public static string? load_error = null;

        public static GenericArray<VmModel> load_vms(string? config_path = null) {
            var list = new GenericArray<VmModel>();
            load_error = null;
            string path = config_path ?? get_vms_file();

            if (!FileUtils.test(path, FileTest.EXISTS)) {
                return list;
            }

            try {
                var parser = new Json.Parser();
                parser.load_from_file(path);
                var root = parser.get_root();
                if (root != null && root.get_node_type() == Json.NodeType.ARRAY) {
                    var array = root.get_array();
                    var ids = new HashTable<string, bool>(str_hash, str_equal);
                    for (uint i = 0; i < array.get_length(); i++) {
                        var node = array.get_element(i);
                        if (!valid_entry(node, ids)) {
                            load_error = _("The resource configuration contains invalid or duplicate entries. Repair vms.json or restore a backup.");
                            return new GenericArray<VmModel>();
                        }
                        list.add(VmModel.from_json_node(node));
                    }
                } else {
                    load_error = _("The resource configuration must contain a JSON array.");
                }
            } catch (Error e) {
                load_error = _("The resource configuration could not be read. Repair vms.json or restore a backup.");
                return list;
            }

            return list;
        }

        private static bool valid_entry(Json.Node node, HashTable<string, bool> ids) {
            if (node.get_node_type() != Json.NodeType.OBJECT) return false;
            var obj = node.get_object();
            string[] keys = {"id", "name", "subtitle", "type", "icon", "dir", "start_cmd", "stop_cmd",
                "connect_cmd", "details", "container_name", "process_name", "monitor_socket", "attached_iso",
                "qmp_socket", "guest_agent_socket", "guest_os", "runtime", "resource_id", "connection_uri"};
            foreach (string key in keys) {
                if (!obj.has_member(key)) continue;
                var value = obj.get_member(key);
                if (value.get_node_type() != Json.NodeType.VALUE || value.get_value_type() != typeof(string)) return false;
            }
            if (!obj.has_member("id") || !obj.has_member("name")) return false;
            string id = obj.get_string_member("id");
            if (id.length == 0 || obj.get_string_member("name").strip().length == 0 || ids.contains(id)) return false;
            ids.insert(id, true);
            return true;
        }

        public static void save_vms(GenericArray<VmModel> vms) {
            if (load_error != null) return;
            string dir = get_config_dir();
            DirUtils.create_with_parents(dir, 0755);

            var array = new Json.Array();
            for (int i = 0; i < vms.length; i++) {
                var node = new Json.Node(Json.NodeType.OBJECT);
                node.set_object(vms[i].to_json_object());
                array.add_element(node);
            }

            var root = new Json.Node(Json.NodeType.ARRAY);
            root.set_array(array);

            var generator = new Json.Generator();
            generator.set_root(root);
            generator.set_pretty(true);

            try {
                generator.to_file(get_vms_file());
            } catch (Error e) {
                warning("Failed to save vms.json: %s", e.message);
            }
        }

    }
}
