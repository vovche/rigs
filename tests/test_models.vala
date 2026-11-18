/* test_models.vala — GLib.Test suite for Rigs data models and JSON */

using Rigs;

namespace Rigs.Tests {

    public class TestModels {
        public static void test_resource_defaults() {
            var resource = new Resource();
            assert(resource.id == "");
            assert(resource.name == "");
            assert(resource.kind == ResourceKind.COMPOSE);
            assert(resource.icon == "computer-symbolic");
            assert(resource.attached_iso == "");
            assert(resource.qmp_socket == "");
            assert(resource.guest_agent_socket == "");
            assert(resource.guest_os == "");
        }

        public static void test_resource_json_roundtrip() {
            var original = new Resource();
            original.id = "test-vm";
            original.name = "Test Virtual Machine";
            original.subtitle = "Ubuntu 24.04 • QEMU";
            original.kind = ResourceKind.QEMU;
            original.icon = "distributor-logo-ubuntu";
            original.dir = "/var/lib/vms/test";
            original.start_cmd = "qemu-system-x86_64";
            original.stop_cmd = "pkill qemu";
            original.connect_cmd = "remote-viewer spice://127.0.0.1:5900";
            original.details = "SPICE :5900";
            original.process_match = "qemu-test";
            original.monitor_socket = "/tmp/qemu-test.sock";
            original.attached_iso = "/srv/isos/ubuntu.iso";
            original.qmp_socket = "/tmp/rigs-test-qmp.sock";
            original.guest_agent_socket = "/tmp/rigs-test-qga.sock";
            original.guest_os = "windows";
            original.runtime = ContainerRuntime.DOCKER;
            original.resource_id = "0123456789abcdef";

            var json_obj = original.to_json_object();
            var node = new Json.Node(Json.NodeType.OBJECT);
            node.set_object(json_obj);

            var parsed = Resource.from_json_node(node);
            assert(parsed.id == "test-vm");
            assert(parsed.name == "Test Virtual Machine");
            assert(parsed.subtitle == "Ubuntu 24.04 • QEMU");
            assert(parsed.kind == ResourceKind.QEMU);
            assert(parsed.icon == "distributor-logo-ubuntu");
            assert(parsed.dir == "/var/lib/vms/test");
            assert(parsed.start_cmd == "qemu-system-x86_64");
            assert(parsed.stop_cmd == "pkill qemu");
            assert(parsed.connect_cmd == "remote-viewer spice://127.0.0.1:5900");
            assert(parsed.details == "SPICE :5900");
            assert(parsed.process_match == "qemu-test");
            assert(parsed.monitor_socket == "/tmp/qemu-test.sock");
            assert(parsed.attached_iso == "/srv/isos/ubuntu.iso");
            assert(parsed.qmp_socket == original.qmp_socket);
            assert(parsed.guest_agent_socket == original.guest_agent_socket);
            assert(parsed.guest_os == "windows");
            assert(parsed.runtime == ContainerRuntime.DOCKER);
            assert(parsed.resource_id == original.resource_id);
        }

        public static void test_resource_empty_json() {
            var node = new Json.Node(Json.NodeType.OBJECT);
            node.set_object(new Json.Object());

            var parsed = Resource.from_json_node(node);
            assert(parsed.id == "");
            assert(parsed.name == "");
            assert(parsed.attached_iso == "");
        }

        public static void test_empty_configuration() {
            try {
                string dir = DirUtils.make_tmp("rigs-config-test-XXXXXX");
                string path = Path.build_filename(dir, "vms.json");
                assert(ResourceStore.load(path).length == 0);
                assert(!FileUtils.test(path, FileTest.EXISTS));
                FileUtils.set_contents(path, "[]");
                assert(ResourceStore.load(path).length == 0);
                FileUtils.set_contents(path, "broken configuration");
                assert(ResourceStore.load(path).length == 0);
                assert(ResourceStore.load_error != null);
                string contents;
                FileUtils.get_contents(path, out contents);
                assert(contents == "broken configuration");
                FileUtils.set_contents(path, "[{\"id\":\"a\",\"name\":\"A\",\"runtime\":42}]");
                assert(ResourceStore.load(path).length == 0 && ResourceStore.load_error != null);
                // Unknown kinds and runtimes are rejected, never mapped to a command.
                FileUtils.set_contents(path, "[{\"id\":\"a\",\"name\":\"A\",\"runtime\":\"/bin/bash\"}]");
                assert(ResourceStore.load(path).length == 0 && ResourceStore.load_error != null);
                FileUtils.set_contents(path, "[{\"id\":\"a\",\"name\":\"A\",\"type\":\"hyperv\"}]");
                assert(ResourceStore.load(path).length == 0 && ResourceStore.load_error != null);
                FileUtils.set_contents(path, "[{\"id\":\"a\",\"name\":\"A\"},{\"id\":\"a\",\"name\":\"B\"}]");
                assert(ResourceStore.load(path).length == 0 && ResourceStore.load_error != null);
                FileUtils.unlink(path);
                ResourceStore.load(path); // Reset the test-local error.
                DirUtils.remove(dir);
            } catch (Error e) { assert_not_reached(); }
        }
    }
}
