/* test_search_provider.vala — Unit tests for GNOME Shell Search Provider */

namespace Rigs.Tests {

    public class TestSearchProvider {

        private static GenericArray<Resource> create_sample_resources() {
            var list = new GenericArray<Resource>();

            var vm1 = new Resource();
            vm1.id = "debian-12";
            vm1.name = "Debian 12 Dev";
            vm1.subtitle = "QEMU/KVM micro-VM";
            vm1.kind = "qemu";
            vm1.icon = "computer-symbolic";
            vm1.details = "RAM: 4 GB • CPUs: 2 • Ports: 2222:22";
            list.add(vm1);

            var vm2 = new Resource();
            vm2.id = "postgres-16";
            vm2.name = "PostgreSQL 16";
            vm2.subtitle = "Docker Compose Stack";
            vm2.kind = "compose";
            vm2.icon = "server-database-symbolic";
            vm2.details = "Services: db, pgadmin • Ports: 5432:5432";
            list.add(vm2);

            var vm3 = new Resource();
            vm3.id = "alpine-min";
            vm3.name = "Alpine Minimal";
            vm3.subtitle = "QEMU/KVM micro-VM";
            vm3.kind = "qemu";
            vm3.icon = "utilities-terminal-symbolic";
            vm3.details = "RAM: 512 MB • CPUs: 1";
            list.add(vm3);

            return list;
        }

        public static void test_initial_search_by_name() {
            var resources = create_sample_resources();
            var provider = new SearchProvider(null, resources);

            try {
                string[] res = provider.get_initial_result_set({ "debian" });
                assert(res.length == 1);
                assert(res[0] == "debian-12");

                string[] res_case = provider.get_initial_result_set({ "POSTGRES" });
                assert(res_case.length == 1);
                assert(res_case[0] == "postgres-16");
            } catch (GLib.Error e) {
                assert_not_reached();
            }
        }

        public static void test_initial_search_by_port_and_type() {
            var resources = create_sample_resources();
            var provider = new SearchProvider(null, resources);

            try {
                // By port
                string[] res_port = provider.get_initial_result_set({ "5432" });
                assert(res_port.length == 1);
                assert(res_port[0] == "postgres-16");

                // By vm_type
                string[] res_type = provider.get_initial_result_set({ "qemu" });
                assert(res_type.length == 2);
                assert(res_type[0] == "debian-12");
                assert(res_type[1] == "alpine-min");

                // Logical AND: multiple terms
                string[] res_and = provider.get_initial_result_set({ "qemu", "alpine" });
                assert(res_and.length == 1);
                assert(res_and[0] == "alpine-min");

                // Non-matching query
                string[] res_none = provider.get_initial_result_set({ "windows" });
                assert(res_none.length == 0);
            } catch (GLib.Error e) {
                assert_not_reached();
            }
        }

        public static void test_subsearch() {
            var resources = create_sample_resources();
            var provider = new SearchProvider(null, resources);

            try {
                string[] prev = { "debian-12", "alpine-min" };
                string[] sub = provider.get_subsearch_result_set(prev, { "alpine" });
                assert(sub.length == 1);
                assert(sub[0] == "alpine-min");

                string[] sub_empty = provider.get_subsearch_result_set(prev, { "postgres" });
                assert(sub_empty.length == 0);
            } catch (GLib.Error e) {
                assert_not_reached();
            }
        }

        public static void test_result_metas() {
            var resources = create_sample_resources();
            var provider = new SearchProvider(null, resources);

            try {
                string[] ids = { "postgres-16", "debian-12" };
                var metas = provider.get_result_metas(ids);
                assert(metas.length == 2);

                // Check first meta (postgres-16)
                var m1 = metas[0];
                assert(m1.lookup("id").get_string() == "postgres-16");
                assert(m1.lookup("name").get_string() == "PostgreSQL 16");
                assert(m1.lookup("description").get_string().contains("5432"));
                assert(m1.lookup("gicon").get_string() == "server-database-symbolic");
                assert(m1.lookup("icon") != null);

                // Check second meta (debian-12)
                var m2 = metas[1];
                assert(m2.lookup("id").get_string() == "debian-12");
                assert(m2.lookup("name").get_string() == "Debian 12 Dev");
                assert(m2.lookup("description").get_string().contains("QEMU/KVM"));
            } catch (GLib.Error e) {
                assert_not_reached();
            }
        }
    }
}
