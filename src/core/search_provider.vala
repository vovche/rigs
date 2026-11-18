/* search_provider.vala — GNOME Shell Search Provider v2 for Rigs */

using GLib;

namespace Rigs {

    public interface SearchTarget : Object {
        public abstract GenericArray<Resource> get_resources();
        public abstract void focus_resource(string id);
        public abstract void set_search_query(string query);
        // Abstract on purpose: a default no-op body would silently shadow GApplication.hold().
        public abstract void begin_query();
        public abstract void end_query();
    }

    [DBus (name = "org.gnome.Shell.SearchProvider2")]
    public class SearchProvider : Object {
        private weak SearchTarget? target;
        private GenericArray<Resource>? override_resources;

        public SearchProvider(SearchTarget? target = null, GenericArray<Resource>? test_resources = null) {
            this.target = target;
            this.override_resources = test_resources;
        }

        private GenericArray<Resource> get_resources() {
            if (override_resources != null) {
                return override_resources;
            }
            if (target != null) {
                return target.get_resources();
            }
            return ResourceStore.load();
        }

        private bool matches(Resource resource, string[] terms) {
            foreach (string term in terms) {
                string t = term.strip().down();
                if (t.length == 0) continue;

                bool term_matched = false;
                if (resource.name.down().contains(t)) term_matched = true;
                else if (resource.subtitle.down().contains(t)) term_matched = true;
                else if (resource.details.down().contains(t)) term_matched = true;
                else if (resource.kind.down().contains(t)) term_matched = true;
                else if (resource.container_name.down().contains(t)) term_matched = true;
                else if (resource.process_match.down().contains(t)) term_matched = true;

                if (!term_matched) {
                    return false;
                }
            }
            return true;
        }

        public string[] get_initial_result_set(string[] terms) throws GLib.Error {
            if (target != null) target.begin_query();
            var matched_ids = new GenericArray<string>();
            var resources = get_resources();

            for (int i = 0; i < resources.length; i++) {
                var resource = resources[i];
                if (matches(resource, terms)) {
                    matched_ids.add(resource.id);
                }
            }

            string[] results = new string[matched_ids.length];
            for (int i = 0; i < matched_ids.length; i++) {
                results[i] = matched_ids[i];
            }
            if (target != null) target.end_query();
            return results;
        }

        public string[] get_subsearch_result_set(string[] previous_results, string[] terms) throws GLib.Error {
            if (target != null) target.begin_query();
            var matched_ids = new GenericArray<string>();
            var resources = get_resources();

            var prev_set = new HashTable<string, bool>(str_hash, str_equal);
            foreach (string prev_id in previous_results) {
                prev_set.insert(prev_id, true);
            }

            for (int i = 0; i < resources.length; i++) {
                var resource = resources[i];
                if (prev_set.contains(resource.id) && matches(resource, terms)) {
                    matched_ids.add(resource.id);
                }
            }

            string[] results = new string[matched_ids.length];
            for (int i = 0; i < matched_ids.length; i++) {
                results[i] = matched_ids[i];
            }
            if (target != null) target.end_query();
            return results;
        }

        public HashTable<string, Variant>[] get_result_metas(string[] results) throws GLib.Error {
            if (target != null) target.begin_query();
            var resources = get_resources();
            var resource_map = new HashTable<string, Resource>(str_hash, str_equal);
            for (int i = 0; i < resources.length; i++) {
                resource_map.insert(resources[i].id, resources[i]);
            }

            var metas = new GenericArray<HashTable<string, Variant>>();

            for (int i = 0; i < results.length; i++) {
                string id = results[i];
                Resource? resource = resource_map.lookup(id);
                if (resource != null) {
                    var meta = new HashTable<string, Variant>(str_hash, str_equal);
                    meta.insert("id", new Variant.string(resource.id));
                    meta.insert("name", new Variant.string(resource.name));

                    string desc = resource.subtitle;
                    if (resource.details.length > 0) {
                        desc = desc + " • " + resource.details;
                    }
                    meta.insert("description", new Variant.string(desc));

                    string icon_name = (resource.icon.length > 0) ? resource.icon : "io.github.vovche.Rigs";
                    var icon = new ThemedIcon(icon_name);
                    meta.insert("gicon", new Variant.string(icon.to_string()));
                    var serialized_icon = icon.serialize();
                    if (serialized_icon != null) {
                        meta.insert("icon", serialized_icon);
                    }

                    metas.add(meta);
                }
            }

            var out_metas = new HashTable<string, Variant>[metas.length];
            for (int i = 0; i < metas.length; i++) {
                out_metas[i] = metas[i];
            }
            if (target != null) target.end_query();
            return out_metas;
        }

        public void activate_result(string id, string[] terms, uint32 timestamp) throws GLib.Error {
            if (target != null) {
                target.begin_query();
                target.focus_resource(id);
                target.end_query();
            }
        }

        public void launch_search(string[] terms, uint32 timestamp) throws GLib.Error {
            if (target != null) {
                target.begin_query();
                target.set_search_query(string.joinv(" ", terms));
                target.end_query();
            }
        }
    }
}
