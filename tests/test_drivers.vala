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
            assert(driver.kind == "qemu");
        }

        public static void test_compose_driver_lookup() {
            var registry = DriverRegistry.get_default();
            var driver = registry.get_driver("compose");
            assert(driver != null);
            assert(driver.kind == "compose");
        }

        public static void test_fallback_driver_lookup() {
            var registry = DriverRegistry.get_default();
            var driver = registry.get_driver("unknown_driver_type");
            assert(driver == null);
        }

        public static void test_qemu_stopped_status() {
            var driver = DriverRegistry.get_default().get_driver("qemu");
            var resource = new Resource();
            resource.id = "non-existent-vm";
            resource.process_match = "definitely_not_running_process_xyz_12345";
            resource.kind = "qemu";

            var st = driver.check_status(resource);
            assert(!st.running);
            assert(st.cpu_pct == 0.0);
            assert(st.ram_str == "0 MB");
        }

        public static void test_compose_stopped_status() {
            var driver = DriverRegistry.get_default().get_driver("compose");
            var resource = new Resource();
            resource.id = "non-existent-compose";
            resource.container_name = "definitely_not_running_container_xyz_12345";
            resource.kind = "compose";

            var st = driver.check_status(resource);
            assert(!st.running);
            assert(st.cpu_pct == 0.0);
            assert(st.ram_str == "0 MB");
        }

        public static void test_compose_missing_container_detection() {
            var missing = new CommandResult("", "Error: no such object: \"tiny10-vm\"\n", 125);
            assert(ComposeDriver.is_missing_container(missing));
            var missing_docker = new CommandResult("", "Error: No such container: win10e-vm\n", 1);
            assert(ComposeDriver.is_missing_container(missing_docker));
            var unreachable = new CommandResult("", "Cannot connect to the Docker daemon\n", 1);
            assert(!ComposeDriver.is_missing_container(unreachable));
        }

        public static void test_qemu_start_spawns_process() {
            var driver = DriverRegistry.get_default().get_driver("qemu");
            var resource = new Resource();
            resource.id = "test-qemu";
            resource.kind = "qemu";
            string marker = "/tmp/rigs-test-qemu-marker-" + Random.next_int().to_string();
            resource.start_cmd = "touch " + marker;
            driver.start(resource);

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
            var resource = new Resource();
            resource.id = "test-compose";
            resource.kind = "compose";
            string marker = "/tmp/rigs-test-compose-marker-" + Random.next_int().to_string();
            resource.start_cmd = "touch " + marker;
            driver.start(resource);

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
            assert(retrieved.kind == "test_hypervisor");

            var resource = new Resource();
            resource.id = "mock-vm-1";
            retrieved.start(resource);
            retrieved.open_console(resource);
            retrieved.stop(resource);
            retrieved.insert_iso(resource, "/tmp/test.iso");
            retrieved.eject_iso(resource);

            assert(mock.started.length == 1);
            assert(mock.started[0] == "mock-vm-1");
            assert(mock.connected.length == 1);
            assert(mock.stopped.length == 1);
            assert(mock.inserted_isos.lookup("mock-vm-1") == "/tmp/test.iso");
            assert(mock.ejected_isos.length == 1);

            mock.reset();
            assert(mock.started.length == 0);
        }
    }
}
