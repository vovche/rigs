/* search_provider.vala — GNOME Shell Search Provider v2 for Rigs */

using GLib;

namespace Rigs {

    public interface SearchTarget : Object {
        public abstract GenericArray<VmModel> get_vms();
        public abstract void focus_vm(string id);
        public abstract void set_search_query(string query);
        public virtual void hold() {}
        public virtual void release() {}
    }

    [DBus (name = "org.gnome.Shell.SearchProvider2")]
    public class SearchProvider : Object {
        private weak SearchTarget? target;
        private GenericArray<VmModel>? override_vms;

        public SearchProvider(SearchTarget? target = null, GenericArray<VmModel>? test_vms = null) {
            this.target = target;
            this.override_vms = test_vms;
        }

        private GenericArray<VmModel> get_vms() {
            if (override_vms != null) {
                return override_vms;
            }
            if (target != null) {
                return target.get_vms();
            }
            return ConfigManager.load_vms();
        }

        private bool matches(VmModel vm, string[] terms) {
            foreach (string term in terms) {
                string t = term.strip().down();
                if (t.length == 0) continue;

                bool term_matched = false;
                if (vm.name.down().contains(t)) term_matched = true;
                else if (vm.subtitle.down().contains(t)) term_matched = true;
                else if (vm.details.down().contains(t)) term_matched = true;
                else if (vm.vm_type.down().contains(t)) term_matched = true;
                else if (vm.container_name.down().contains(t)) term_matched = true;
                else if (vm.process_name.down().contains(t)) term_matched = true;

                if (!term_matched) {
                    return false;
                }
            }
            return true;
        }

        public string[] get_initial_result_set(string[] terms) throws GLib.Error {
            if (target != null) target.hold();
            var matched_ids = new GenericArray<string>();
            var vms = get_vms();

            for (int i = 0; i < vms.length; i++) {
                var vm = vms[i];
                if (matches(vm, terms)) {
                    matched_ids.add(vm.id);
                }
            }

            string[] results = new string[matched_ids.length];
            for (int i = 0; i < matched_ids.length; i++) {
                results[i] = matched_ids[i];
            }
            if (target != null) target.release();
            return results;
        }

        public string[] get_subsearch_result_set(string[] previous_results, string[] terms) throws GLib.Error {
            if (target != null) target.hold();
            var matched_ids = new GenericArray<string>();
            var vms = get_vms();

            var prev_set = new HashTable<string, bool>(str_hash, str_equal);
            foreach (string prev_id in previous_results) {
                prev_set.insert(prev_id, true);
            }

            for (int i = 0; i < vms.length; i++) {
                var vm = vms[i];
                if (prev_set.contains(vm.id) && matches(vm, terms)) {
                    matched_ids.add(vm.id);
                }
            }

            string[] results = new string[matched_ids.length];
            for (int i = 0; i < matched_ids.length; i++) {
                results[i] = matched_ids[i];
            }
            if (target != null) target.release();
            return results;
        }

        public HashTable<string, Variant>[] get_result_metas(string[] results) throws GLib.Error {
            if (target != null) target.hold();
            var vms = get_vms();
            var vm_map = new HashTable<string, VmModel>(str_hash, str_equal);
            for (int i = 0; i < vms.length; i++) {
                vm_map.insert(vms[i].id, vms[i]);
            }

            var metas = new GenericArray<HashTable<string, Variant>>();

            for (int i = 0; i < results.length; i++) {
                string id = results[i];
                VmModel? vm = vm_map.lookup(id);
                if (vm != null) {
                    var meta = new HashTable<string, Variant>(str_hash, str_equal);
                    meta.insert("id", new Variant.string(vm.id));
                    meta.insert("name", new Variant.string(vm.name));

                    string desc = vm.subtitle;
                    if (vm.details.length > 0) {
                        desc = desc + " • " + vm.details;
                    }
                    meta.insert("description", new Variant.string(desc));

                    string icon_name = (vm.icon.length > 0) ? vm.icon : "io.github.vovche.Rigs";
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
            if (target != null) target.release();
            return out_metas;
        }

        public void activate_result(string id, string[] terms, uint32 timestamp) throws GLib.Error {
            if (target != null) {
                target.hold();
                target.focus_vm(id);
                target.release();
            }
        }

        public void launch_search(string[] terms, uint32 timestamp) throws GLib.Error {
            if (target != null) {
                target.hold();
                target.set_search_query(string.joinv(" ", terms));
                target.release();
            }
        }
    }
}
