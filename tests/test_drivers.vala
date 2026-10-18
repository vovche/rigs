/* test_drivers.vala — GLib.Test suite for DriverRegistry and Drivers */

using Rigs;

namespace Rigs.Tests {

    public class TestDrivers {
        public static void test_registry_singleton() {
            var r1 = DriverRegistry.get_default();
            var r2 = DriverRegistry.get_default();
            assert(r1 != null);
            assert(r1 == r2);
        }

        public static void test_qemu_driver_lookup() {
            var registry = DriverRegistry.get_default();
            var driver = registry.get_driver("qemu");
            assert(driver != null);
            assert(driver.vm_type == "qemu");
        }

        public static void test_compose_driver_lookup() {
            var registry = DriverRegistry.get_default();
            var driver = registry.get_driver("compose");
            assert(driver != null);
            assert(driver.vm_type == "compose");
        }

        public static void test_fallback_driver_lookup() {
            var registry = DriverRegistry.get_default();
            var driver = registry.get_driver("unknown_driver_type");
            assert(driver == null);
        }

        public static void test_qemu_stopped_status() {
            var driver = DriverRegistry.get_default().get_driver("qemu");
            var vm = new VmModel();
            vm.id = "non-existent-vm";
            vm.process_name = "definitely_not_running_process_xyz_12345";
            vm.vm_type = "qemu";

            var st = driver.check_status(vm);
            assert(!st.running);
            assert(st.cpu_pct == 0.0);
            assert(st.ram_str == "0 MB");
        }

        public static void test_compose_stopped_status() {
            var driver = DriverRegistry.get_default().get_driver("compose");
            var vm = new VmModel();
            vm.id = "non-existent-compose";
            vm.container_name = "definitely_not_running_container_xyz_12345";
            vm.vm_type = "compose";

            var st = driver.check_status(vm);
            assert(!st.running);
            assert(st.cpu_pct == 0.0);
            assert(st.ram_str == "0 MB");
        }

        public static void test_qemu_start_spawns_process() {
            var driver = DriverRegistry.get_default().get_driver("qemu");
            var vm = new VmModel();
            vm.id = "test-qemu";
            vm.vm_type = "qemu";
            string marker = "/tmp/rigs-test-qemu-marker-" + Random.next_int().to_string();
            vm.start_cmd = "touch " + marker;
            driver.start(vm);

            // Give thread a brief moment to execute
            Thread.usleep(250 * 1000);
            bool exists = FileUtils.test(marker, FileTest.EXISTS);
            if (exists) {
                FileUtils.unlink(marker);
            }
            assert(exists);
        }

        public static void test_compose_start_spawns_process() {
            var driver = DriverRegistry.get_default().get_driver("compose");
            var vm = new VmModel();
            vm.id = "test-compose";
            vm.vm_type = "compose";
            string marker = "/tmp/rigs-test-compose-marker-" + Random.next_int().to_string();
            vm.start_cmd = "touch " + marker;
            driver.start(vm);

            // Give thread a brief moment to execute
            Thread.usleep(250 * 1000);
            bool exists = FileUtils.test(marker, FileTest.EXISTS);
            if (exists) {
                FileUtils.unlink(marker);
            }
            assert(exists);
        }

        public static void test_mock_driver_lifecycle() {
            var mock = new MockDriver("test_hypervisor");
            var registry = DriverRegistry.get_default();
            registry.register_driver(mock);

            var retrieved = registry.get_driver("test_hypervisor");
            assert(retrieved != null);
            assert(retrieved.vm_type == "test_hypervisor");

            var vm = new VmModel();
            vm.id = "mock-vm-1";
            retrieved.start(vm);
            retrieved.connect_vm(vm);
            retrieved.stop(vm);
            retrieved.insert_iso(vm, "/tmp/test.iso");
            retrieved.eject_iso(vm);

            assert(mock.started_vms.length == 1);
            assert(mock.started_vms[0] == "mock-vm-1");
            assert(mock.connected_vms.length == 1);
            assert(mock.stopped_vms.length == 1);
            assert(mock.inserted_isos.lookup("mock-vm-1") == "/tmp/test.iso");
            assert(mock.ejected_isos.length == 1);

            mock.reset();
            assert(mock.started_vms.length == 0);
        }
    }
}
