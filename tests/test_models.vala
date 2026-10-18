/* test_models.vala — GLib.Test suite for Rigs data models and JSON */

using Rigs;

namespace Rigs.Tests {

    public class TestModels {
        public static void test_vm_model_defaults() {
            var vm = new VmModel();
            assert(vm.id == "");
            assert(vm.name == "");
            assert(vm.vm_type == "compose");
            assert(vm.icon == "computer-symbolic");
            assert(vm.attached_iso == "");
            assert(vm.qmp_socket == "");
            assert(vm.guest_agent_socket == "");
            assert(vm.guest_os == "");
        }

        public static void test_vm_model_json_roundtrip() {
            var original = new VmModel();
            original.id = "test-vm";
            original.name = "Test Virtual Machine";
            original.subtitle = "Ubuntu 24.04 • QEMU";
            original.vm_type = "qemu";
            original.icon = "distributor-logo-ubuntu";
            original.dir = "/var/lib/vms/test";
            original.start_cmd = "qemu-system-x86_64";
            original.stop_cmd = "pkill qemu";
            original.connect_cmd = "remote-viewer spice://127.0.0.1:5900";
            original.details = "SPICE :5900";
            original.process_name = "qemu-test";
            original.monitor_socket = "/tmp/qemu-test.sock";
            original.attached_iso = "/srv/isos/ubuntu.iso";
            original.qmp_socket = "/tmp/rigs-test-qmp.sock";
            original.guest_agent_socket = "/tmp/rigs-test-qga.sock";
            original.guest_os = "windows";
            original.runtime = "docker";
            original.resource_id = "0123456789abcdef";

            var json_obj = original.to_json_object();
            var node = new Json.Node(Json.NodeType.OBJECT);
            node.set_object(json_obj);

            var parsed = VmModel.from_json_node(node);
            assert(parsed.id == "test-vm");
            assert(parsed.name == "Test Virtual Machine");
            assert(parsed.subtitle == "Ubuntu 24.04 • QEMU");
            assert(parsed.vm_type == "qemu");
            assert(parsed.icon == "distributor-logo-ubuntu");
            assert(parsed.dir == "/var/lib/vms/test");
            assert(parsed.start_cmd == "qemu-system-x86_64");
            assert(parsed.stop_cmd == "pkill qemu");
            assert(parsed.connect_cmd == "remote-viewer spice://127.0.0.1:5900");
            assert(parsed.details == "SPICE :5900");
            assert(parsed.process_name == "qemu-test");
            assert(parsed.monitor_socket == "/tmp/qemu-test.sock");
            assert(parsed.attached_iso == "/srv/isos/ubuntu.iso");
            assert(parsed.qmp_socket == original.qmp_socket);
            assert(parsed.guest_agent_socket == original.guest_agent_socket);
            assert(parsed.guest_os == "windows");
            assert(parsed.runtime == "docker");
            assert(parsed.resource_id == original.resource_id);
        }

        public static void test_vm_model_empty_json() {
            var node = new Json.Node(Json.NodeType.OBJECT);
            node.set_object(new Json.Object());

            var parsed = VmModel.from_json_node(node);
            assert(parsed.id == "");
            assert(parsed.name == "");
            assert(parsed.attached_iso == "");
        }

        public static void test_empty_configuration() {
            try {
                string dir = DirUtils.make_tmp("rigs-config-test-XXXXXX");
                string path = Path.build_filename(dir, "vms.json");
                assert(ConfigManager.load_vms(path).length == 0);
                assert(!FileUtils.test(path, FileTest.EXISTS));
                FileUtils.set_contents(path, "[]");
                assert(ConfigManager.load_vms(path).length == 0);
                FileUtils.set_contents(path, "broken configuration");
                assert(ConfigManager.load_vms(path).length == 0);
                assert(ConfigManager.load_error != null);
                string contents;
                FileUtils.get_contents(path, out contents);
                assert(contents == "broken configuration");
                FileUtils.set_contents(path, "[{\"id\":\"a\",\"name\":\"A\",\"runtime\":42}]");
                assert(ConfigManager.load_vms(path).length == 0 && ConfigManager.load_error != null);
                FileUtils.set_contents(path, "[{\"id\":\"a\",\"name\":\"A\"},{\"id\":\"a\",\"name\":\"B\"}]");
                assert(ConfigManager.load_vms(path).length == 0 && ConfigManager.load_error != null);
                FileUtils.unlink(path);
                ConfigManager.load_vms(path); // Reset the test-local error.
                DirUtils.remove(dir);
            } catch (Error e) { assert_not_reached(); }
        }
    }
}
