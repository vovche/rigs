/* window_state.vala — the main window's remembered size and expanded cards (state.json).
 * Pure data + JSON so it is testable without GTK; Window debounces the writes. */
namespace Rigs {
    public class WindowState : Object {
        public const int MIN_SIZE = 360;
        public const int MAX_SIZE = 8192;

        // The unmaximized size (GTK default-width/height), never the maximized one.
        public int width = 580;
        public int height = 740;
        public bool maximized = false;
        // resource.id → expanded; ids of removed resources are simply ignored.
        public HashTable<string, bool> expanded = new HashTable<string, bool>(str_hash, str_equal);

        public static string default_path() {
            return Path.build_filename(ResourceStore.get_config_dir(), "state.json");
        }

        // A missing or damaged file yields the defaults: window state is a convenience.
        public static WindowState load(string path) {
            var state = new WindowState();
            try {
                var parser = new Json.Parser();
                parser.load_from_file(path);
                var root = parser.get_root();
                if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return state;
                unowned Json.Object obj = root.get_object();
                if (obj.has_member("window") && obj.get_member("window").get_node_type() == Json.NodeType.OBJECT) {
                    unowned Json.Object win = obj.get_object_member("window");
                    state.width = read_size(win, "width", state.width);
                    state.height = read_size(win, "height", state.height);
                    if (win.has_member("maximized") && win.get_member("maximized").get_value_type() == typeof(bool))
                        state.maximized = win.get_boolean_member("maximized");
                }
                if (obj.has_member("expanded") && obj.get_member("expanded").get_node_type() == Json.NodeType.OBJECT) {
                    var exp = obj.get_object_member("expanded");
                    foreach (string id in exp.get_members()) {
                        var node = exp.get_member(id);
                        if (node.get_value_type() == typeof(bool)) state.expanded.insert(id, node.get_boolean());
                    }
                }
            } catch (Error e) {
                // Defaults.
            }
            return state;
        }

        private static int read_size(Json.Object win, string key, int fallback) {
            if (!win.has_member(key) || win.get_member(key).get_value_type() != typeof(int64)) return fallback;
            return ((int) win.get_int_member(key)).clamp(MIN_SIZE, MAX_SIZE);
        }

        public void save(string path) throws Error {
            DirUtils.create_with_parents(Path.get_dirname(path), 0755);
            var win = new Json.Object();
            win.set_int_member("width", width);
            win.set_int_member("height", height);
            win.set_boolean_member("maximized", maximized);
            var exp = new Json.Object();
            expanded.foreach((id, value) => { exp.set_boolean_member(id, value); });
            var root_obj = new Json.Object();
            root_obj.set_object_member("window", win);
            root_obj.set_object_member("expanded", exp);
            var root = new Json.Node(Json.NodeType.OBJECT);
            root.set_object(root_obj);
            var generator = new Json.Generator();
            generator.set_root(root);
            generator.set_pretty(true);
            generator.to_file(path);
        }
    }
}
