using Rigs;

namespace Rigs.Tests {
    private class ManagedCommands : HostCommand {
        public GenericArray<string> calls = new GenericArray<string>();
        public string state = "true\n";
        public string stats = "12.5%\t1.8 GiB / 4 GiB\n";
        public int inspect_exit = 0;
        public int stats_exit = 0;

        public override CommandResult run(string[] argv, string? directory = null, uint timeout_ms = 3000) throws Error {
            calls.add(string.joinv("|", argv));
            if (argv[0] == "virsh") return new CommandResult(state, "", inspect_exit);
            if (argv[1] == "inspect") return new CommandResult(state, "", inspect_exit);
            return new CommandResult(stats, "", stats_exit);
        }

        public override void launch(string[] argv, string? directory = null) throws Error {
            calls.add(string.joinv("|", argv));
        }
    }

    public class TestManagedDriver {
        public static void test_container_status() {
            var commands = new ManagedCommands();
            var driver = new ManagedDriver("container", commands);
            var vm = new VmModel();
            vm.resource_id = "0123456789abcdef";
            vm.runtime = "podman";
            var status = driver.check_status(vm);
            assert(status.status_available && status.running);
            assert(status.cpu_pct == 12.5);
            assert(status.ram_str == "1.8 GiB");
            assert(status.ram_pct == 0 && !status.guest_ram_valid);
            assert(commands.calls[1].contains("{{.CPU}}\t{{.MemUsage}}"));
            vm.runtime = "docker";
            driver.check_status(vm);
            assert(commands.calls[3].contains("{{.CPUPerc}}\t{{.MemUsage}}"));
            commands.stats_exit = 1;
            status = driver.check_status(vm);
            assert(status.status_available && status.running && status.ram_str == "—");
            commands.state = "false\n";
            uint count = commands.calls.length;
            status = driver.check_status(vm);
            assert(status.status_available && !status.running);
            assert(commands.calls.length == count + 1);
            commands.inspect_exit = 1;
            assert(!driver.check_status(vm).status_available);
            commands.inspect_exit = 0;
            commands.state = "garbage";
            assert(!driver.check_status(vm).status_available);
            assert(string.joinv("|", driver.lifecycle_argv(vm, true)) == "docker|start|0123456789abcdef");
            assert(string.joinv("|", driver.lifecycle_argv(vm, false)) == "docker|stop|--time|30|0123456789abcdef");
        }

        public static void test_libvirt_status() {
            var commands = new ManagedCommands();
            var driver = new ManagedDriver("libvirt", commands);
            var vm = new VmModel();
            vm.resource_id = "01234567-89ab-cdef-0123-456789abcdef";
            vm.connection_uri = "qemu:///session";
            commands.state = "Name: example\nState: running\nUsed memory: 4194304 KiB\n";
            var status = driver.check_status(vm);
            assert(status.status_available && status.running);
            assert(status.ram_str == "4194304 KiB" && status.ram_pct == 0);
            foreach (string state in new string[] { "paused", "idle", "in shutdown", "pmsuspended" }) {
                commands.state = "State: " + state + "\n";
                assert(driver.check_status(vm).running);
            }
            commands.state = "State: shut off\n";
            status = driver.check_status(vm);
            assert(status.status_available && !status.running);
            commands.state = "not dominfo";
            assert(!driver.check_status(vm).status_available);
            assert(string.joinv("|", driver.lifecycle_argv(vm, false)) ==
                "virsh|--connect|qemu:///session|shutdown|" + vm.resource_id);
            driver.connect_vm(vm);
            assert(commands.calls[commands.calls.length - 1] ==
                "virt-viewer|--connect|qemu:///session|" + vm.resource_id);
        }

        public static void test_invalid_targets() {
            var commands = new ManagedCommands();
            var container = new ManagedDriver("container", commands);
            var vm = new VmModel();
            vm.resource_id = "--all";
            assert(!container.check_status(vm).status_available);
            assert(container.lifecycle_argv(vm, false).length == 0);
            container.connect_vm(vm);
            vm.resource_id = "0123456789abcdef";
            vm.runtime = "/bin/bash";
            assert(!container.check_status(vm).status_available);
            assert(container.lifecycle_argv(vm, true).length == 0);
            var libvirt = new ManagedDriver("libvirt", commands);
            vm.resource_id = "01234567-89ab-cdef-0123-456789abcdef";
            vm.connection_uri = "qemu+ssh://host/system";
            assert(!libvirt.check_status(vm).status_available);
            assert(libvirt.lifecycle_argv(vm, false).length == 0);
            libvirt.connect_vm(vm);
            vm.connection_uri = "qemu:///system";
            vm.resource_id = "example";
            assert(!libvirt.check_status(vm).status_available);
            assert(commands.calls.length == 0);
        }
    }
}
