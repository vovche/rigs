using GLib.Intl;

/* resource_store.vala — loads and saves the user's resources (~/.config/rigs/vms.json).
 * The file format keeps its historical keys ("type", "process_name"); see Resource.from_json_node. */
namespace Rigs {
    public class ResourceStore : Object {
        public static string get_config_dir() {
            return Path.build_filename(Environment.get_user_config_dir(), "rigs");
        }

        public static string resources_file() {
            return Path.build_filename(get_config_dir(), "vms.json");
        }

        public static string get_state_file() {
            return Path.build_filename(get_config_dir(), "state.json");
        }

        public static string? load_error = null;

        public static GenericArray<Resource> load(string? config_path = null) {
            var list = new GenericArray<Resource>();
            load_error = null;
            string path = config_path ?? resources_file();

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
                            return new GenericArray<Resource>();
                        }
                        list.add(Resource.from_json_node(node));
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

        // Why the last save_vms() failed; null after a successful save.
        public static string? save_error = null;

        // Returns false (and sets save_error) when the changes did not reach the disk.
        public static bool save(GenericArray<Resource> resources) {
            if (load_error != null) {
                save_error = _("Changes are not saved while vms.json needs repair.");
                return false;
            }
            string dir = get_config_dir();
            if (DirUtils.create_with_parents(dir, 0755) != 0) {
                save_error = _("Cannot create %s: %s").printf(dir, strerror(errno));
                return false;
            }

            var array = new Json.Array();
            for (int i = 0; i < resources.length; i++) {
                var node = new Json.Node(Json.NodeType.OBJECT);
                node.set_object(resources[i].to_json_object());
                array.add_element(node);
            }

            var root = new Json.Node(Json.NodeType.ARRAY);
            root.set_array(array);

            var generator = new Json.Generator();
            generator.set_root(root);
            generator.set_pretty(true);

            try {
                generator.to_file(resources_file());
            } catch (Error e) {
                save_error = e.message;
                return false;
            }
            save_error = null;
            return true;
        }

    }
}
