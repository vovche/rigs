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
            var driver = registry.get_driver(ResourceKind.QEMU);
            assert(driver != null);
            assert(driver.kind == ResourceKind.QEMU);
        }

        public static void test_compose_driver_lookup() {
            var registry = DriverRegistry.get_default();
            var driver = registry.get_driver(ResourceKind.COMPOSE);
            assert(driver != null);
            assert(driver.kind == ResourceKind.COMPOSE);
        }

        public static void test_fallback_driver_lookup() {
            // An empty registry has no driver; ResourceActions turns that into an issue.
            var registry = new DriverRegistry();
            assert(registry.get_driver(ResourceKind.QEMU) == null);
            var resource = new Resource();
            var issue = new ResourceActions(registry).run_blocking(resource, ResourceOperation.START, (d) => d.start(resource));
            assert(issue != null && issue.category == FailureCategory.UNSUPPORTED);
        }

        public static void test_qemu_stopped_status() {
            var driver = DriverRegistry.get_default().get_driver(ResourceKind.QEMU);
            var resource = new Resource();
            resource.id = "non-existent-vm";
            resource.process_match = "definitely_not_running_process_xyz_12345";
            resource.kind = ResourceKind.QEMU;

            var st = driver.check_status(resource);
            assert(!st.running);
            assert(st.cpu_pct == 0.0);
            assert(st.ram_str == "0 MB");
        }

        public static void test_compose_stopped_status() {
            var driver = DriverRegistry.get_default().get_driver(ResourceKind.COMPOSE);
            var resource = new Resource();
            resource.id = "non-existent-compose";
            resource.container_name = "definitely_not_running_container_xyz_12345";
            resource.kind = ResourceKind.COMPOSE;

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

        // Real processes, bounded: the default drivers run the user's command (no VM involved).
        public static void test_qemu_start_spawns_process() {
            var driver = new ScriptedQemuDriver();
            var resource = new Resource();
            resource.id = "test-qemu";
            resource.kind = ResourceKind.QEMU;
            string marker = Path.build_filename(Environment.get_tmp_dir(), "rigs-test-qemu-marker-" + Random.next_int().to_string());
            resource.start_cmd = "touch " + Shell.quote(marker);
            assert(driver.start(resource) == null);
            bool exists = FileUtils.test(marker, FileTest.EXISTS);
            FileUtils.unlink(marker);
            assert(exists);
        }

        public static void test_compose_start_spawns_process() {
            var driver = new ComposeDriver();
            var resource = new Resource();
            resource.id = "test-compose";
            resource.kind = ResourceKind.COMPOSE;
            string marker = Path.build_filename(Environment.get_tmp_dir(), "rigs-test-compose-marker-" + Random.next_int().to_string());
            resource.start_cmd = "touch " + Shell.quote(marker);
            // No container_name: nothing to check after start, so no settle wait.
            assert(driver.start(resource) == null);
            bool exists = FileUtils.test(marker, FileTest.EXISTS);
            FileUtils.unlink(marker);
            assert(exists);
        }

        public static void test_mock_driver_lifecycle() {
            var mock = new MockDriver(ResourceKind.LIBVIRT);
            var registry = new DriverRegistry();
            registry.register_driver(mock);

            var retrieved = registry.get_driver(ResourceKind.LIBVIRT);
            assert(retrieved != null);
            assert(retrieved.kind == ResourceKind.LIBVIRT);

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

            // ResourceActions stamps the requested operation on whatever the driver returns.
            var actions = new ResourceActions(registry);
            resource.kind = ResourceKind.LIBVIRT;
            mock.next_issue = new ResourceIssue(FailureCategory.GENERIC_ERROR, "x", "y");
            var issue = actions.run_blocking(resource, ResourceOperation.STOP, (d) => d.stop(resource));
            assert(issue != null && issue.operation == ResourceOperation.STOP);
            mock.next_issue.operation = ResourceOperation.RUN;
            issue = actions.run_blocking(resource, ResourceOperation.START, (d) => d.start(resource));
            assert(issue.operation == ResourceOperation.RUN);
        }
    }
}
