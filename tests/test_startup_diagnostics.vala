using Rigs;

namespace Rigs.Tests {
    private class LogCommands : HostCommand {
        public string logs = "";
        public string running = "false\n";
        public GenericArray<string> calls = new GenericArray<string>();
        public int start_exit = 0;
        public string start_stderr = "";

        public override CommandResult run(string[] argv, string? directory = null, uint timeout_ms = 3000) throws Error {
            calls.add(string.joinv("|", argv));
            if (argv[1] == "logs") return new CommandResult("", logs, 0);
            if (argv[1] == "inspect") return new CommandResult(running, "", 0);
            return new CommandResult("", start_stderr, start_exit);
        }
    }

    public class TestStartupDiagnostics {
        public static void test_empty() {
            assert(StartupDiagnostics.analyze("") == null);
            assert(StartupDiagnostics.analyze("  \n ") == null);
        }

        public static void test_mount() {
            var i = StartupDiagnostics.analyze("Error: crun: cannot stat '/srv/tiny10/storage': No such file or directory: OCI runtime attempted to invoke a command that was not found");
            assert(i != null && i.category == FailureCategory.STORAGE_MOUNT);
            assert(i.suggested_command == "mkdir -p '/srv/tiny10/storage'");
            assert(i.matched_snippet.contains("/srv/tiny10/storage"));
            i = StartupDiagnostics.analyze("Error response from daemon: invalid mount config for type \"bind\": bind source path does not exist: /home/u/my data\nmore");
            assert(i.category == FailureCategory.STORAGE_MOUNT);
            assert(i.suggested_command == "mkdir -p '/home/u/my data'");
            // Rootless Podman wording (the tiny10 case).
            i = StartupDiagnostics.analyze("Error: statfs /home/u/vms/tiny10/storage: no such file or directory");
            assert(i.category == FailureCategory.STORAGE_MOUNT);
            assert(i.suggested_command == "mkdir -p '/home/u/vms/tiny10/storage'");
        }

        public static void test_port() {
            var i = StartupDiagnostics.analyze("Error: rootlessport listen tcp 0.0.0.0:3389: bind: address already in use");
            assert(i.category == FailureCategory.NETWORK_PORT);
            assert(i.suggested_command == "ss -tulpn | grep :3389");
            i = StartupDiagnostics.analyze("Bind for 0.0.0.0:8006 failed: port is already allocated");
            assert(i.suggested_command == "ss -tulpn | grep :8006");
            i = StartupDiagnostics.analyze("bind: address already in use");
            assert(i.category == FailureCategory.NETWORK_PORT);
            assert(i.suggested_command.contains("<port>"));
        }

        public static void test_conflict() {
            var i = StartupDiagnostics.analyze("Error: creating container storage: the container name \"tiny10-vm\" is already in use by 3f2a9c1d7b8e4a5f. You have to remove that container");
            assert(i.category == FailureCategory.CONTAINER_CONFLICT);
            assert(i.suggested_command == "podman rm -f 3f2a9c1d7b8e4a5f");
            i = StartupDiagnostics.analyze("Conflict. The container name \"/win10e\" is already in use by container \"abc123def456\". You have to remove it");
            assert(i.suggested_command == "docker rm -f abc123def456");
        }

        public static void test_kvm() {
            var i = StartupDiagnostics.analyze("qemu-system-x86_64: Could not access KVM kernel module: Permission denied");
            assert(i.category == FailureCategory.PERMISSIONS_KVM);
            assert(i.suggested_command == "sudo usermod -aG kvm $USER");
            i = StartupDiagnostics.analyze("error: /dev/kvm: Permission denied");
            assert(i.category == FailureCategory.PERMISSIONS_KVM);
        }

        public static void test_netns() {
            var i = StartupDiagnostics.analyze("Error: rootless netns: kill network process: permission denied");
            assert(i.category == FailureCategory.NETWORK_PORT);
            assert(i.suggested_command == null);
            assert(i.suggested_action.contains("podman system reset"));
        }

        public static void test_oom() {
            var i = StartupDiagnostics.analyze("qemu-system-x86_64: cannot allocate memory");
            assert(i.category == FailureCategory.RESOURCE_EXHAUSTION);
            string plain = i.suggested_action;
            i = StartupDiagnostics.analyze("State: OOMKilled", "windows");
            assert(i.category == FailureCategory.RESOURCE_EXHAUSTION);
            assert(i.suggested_action != plain);
        }

        public static void test_generic_and_limits() {
            var i = StartupDiagnostics.analyze("starting...\nsomething odd happened\n\n");
            assert(i.category == FailureCategory.GENERIC_ERROR);
            assert(i.matched_snippet == "something odd happened");
            // Huge input stays bounded and the tail is still analysed.
            var big = new StringBuilder();
            for (int n = 0; n < 20000; n++) big.append("noise line\n");
            big.append("bind: address already in use :99");
            assert(StartupDiagnostics.analyze(big.str).category == FailureCategory.NETWORK_PORT);
        }

        public static void test_diagnose_logs_fallback() {
            var host = new LogCommands();
            host.logs = "crun: cannot stat '/mnt/x': No such file or directory";
            var i = StartupDiagnostics.diagnose(host, "podman", "tiny10-vm", new CommandResult("", "", 1));
            assert(i.category == FailureCategory.STORAGE_MOUNT);
            assert(host.calls[0] == "podman|logs|--tail=30|tiny10-vm");
            // stderr wins; logs are not read.
            host = new LogCommands();
            i = StartupDiagnostics.diagnose(host, "podman", "tiny10-vm", new CommandResult("", "bind: address already in use", 1));
            assert(i.category == FailureCategory.NETWORK_PORT && host.calls.length == 0);
            // Silent failure still yields an issue; hostile container names are never passed to the runtime.
            i = StartupDiagnostics.diagnose(host, "podman", "-rf", new CommandResult("", "", 3));
            assert(i != null && i.category == FailureCategory.GENERIC_ERROR && host.calls.length == 0);
            assert(StartupDiagnostics.diagnose(host, "podman", "x", new CommandResult("", "", 0)) == null);
        }

        public static void test_managed_start() {
            var host = new LogCommands();
            var driver = new ManagedDriver("container", host);
            driver.settle_ms = 0;
            var vm = new VmModel();
            vm.resource_id = "0123456789abcdef";
            vm.runtime = "podman";
            host.running = "true\n";
            assert(driver.start_blocking(vm) == null);
            host.running = "false\n";
            host.logs = "Error: address already in use 0.0.0.0:5900: bind: address already in use";
            var i = driver.start_blocking(vm);
            assert(i != null && i.category == FailureCategory.NETWORK_PORT);
            host.running = "true\n";
            host.start_exit = 125;
            host.start_stderr = "Error: rootless netns: kill network process: permission denied";
            i = driver.start_blocking(vm);
            assert(i != null && i.suggested_action.contains("podman system reset"));
        }

        public static void test_model_issue() {
            var vm = new VmModel();
            assert(vm.last_startup_issue == null);
            bool fired = false;
            vm.startup_failed.connect((issue) => { fired = true; });
            var issue = StartupDiagnostics.analyze("bind: address already in use");
            vm.last_startup_issue = issue;
            vm.startup_failed(issue);
            assert(fired && vm.last_startup_issue == issue);
        }
    }
}
