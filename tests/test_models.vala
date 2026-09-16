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
        }

        public static void test_vm_model_empty_json() {
            var node = new Json.Node(Json.NodeType.OBJECT);
            node.set_object(new Json.Object());

            var parsed = VmModel.from_json_node(node);
            assert(parsed.id == "");
            assert(parsed.name == "");
            assert(parsed.attached_iso == "");
        }

        public static void test_seed_default_vms() {
            var vms = ConfigManager.seed_default_vms();
            assert(vms.length >= 2);

            bool has_omarchy = false;
            bool has_tiny10 = false;

            for (int i = 0; i < vms.length; i++) {
                if (vms[i].id == "omarchy") has_omarchy = true;
                if (vms[i].id == "tiny10") has_tiny10 = true;
            }

            assert(has_omarchy);
            assert(has_tiny10);
        }
    }
}
