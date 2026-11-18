using GLib.Intl;

namespace Rigs.Tests {
    private class DiscoveryCommands : HostCommand {
        public string podman_output = "";
        public string docker_output = "";
        public string session_output = "";
        public string system_output = "";
        public bool deny_podman = false;
        public bool missing_docker = false;
        public uint calls = 0;

        public DiscoveryCommands() {
            base("native");
        }

        public override CommandResult run(string[] argv, string? directory = null, uint timeout_ms = 3000) throws Error {
            calls++;
            assert(directory == null);
            assert(timeout_ms == 3000);
            if (argv[0] == "podman" || argv[0] == "docker") {
                assert(argv.length == 6);
                assert(argv[1] == "ps" && argv[2] == "--all" && argv[3] == "--no-trunc");
                assert(argv[4] == "--format");
                assert(argv[5] == "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.State}}");
                if (argv[0] == "podman") {
                    if (deny_podman) return new CommandResult("", "permission denied: secret-token", 1);
                    return new CommandResult(podman_output);
                }
                if (missing_docker) throw new SpawnError.NOENT("docker: No such file or directory secret-token");
                return new CommandResult(docker_output);
            }
            assert(argv.length == 8 && argv[0] == "virsh");
            assert(argv[1] == "--readonly" && argv[2] == "--connect" && argv[4] == "list" && argv[5] == "--all");
            assert(argv[6] == "--uuid" && argv[7] == "--name");
            assert(argv[3] == "qemu:///session" || argv[3] == "qemu:///system");
            return new CommandResult(argv[3] == "qemu:///session" ? session_output : system_output);
        }
    }

    public class TestDiscovery {
        private const string CONTAINER_A = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789";
        private const string CONTAINER_B = "012345abcdef";
        private const string DOMAIN = "12345678-abcd-1234-abcd-123456789012";

        public static void test_containers() {
            var commands = new DiscoveryCommands();
            commands.podman_output = CONTAINER_A + "\tmy VM; $(touch impossible)\timage:test\texited\n" +
                "invalid-id\tbad\timage\trunning\n";
            commands.docker_output = CONTAINER_B + "\tother\timage:latest\trunning\n";
            var result = new ResourceDiscovery(commands).scan(new GenericArray<Resource>());
            assert(commands.calls == 4 && result.sources.length == 4);
            assert(result.candidates.length == 2);
            var resource = result.candidates[0];
            assert(resource.id == "podman:" + CONTAINER_A);
            assert(resource.runtime == "podman" && resource.kind == "container");
            assert(resource.name == "my VM; $(touch impossible)" && resource.container_name == resource.name);
            assert(resource.details == "exited" && resource.resource_id == CONTAINER_A);
            assert(resource.start_cmd == "" && resource.stop_cmd == "");
            assert(!result.sources[0].available);
            assert(result.sources[1].available && result.sources[2].available);
            assert(resource.guest_os == "" && resource.qmp_socket == "");

            // Known Windows VM images get setup hints; names and unrelated images do not.
            commands.podman_output =
                "000000000001\tknown\tghcr.io/dockur/windows:latest\trunning\n" +
                "000000000002\tknown-digest\tdocker.io/dockurr/windows@sha256:abcdef\texited\n" +
                "000000000003\tknown-short\tdockurr/windows:4\trunning\n" +
                "000000000004\twindows\tother/windows:latest\trunning\n" +
                "000000000005\twindows\tdockurr/windows-tools:latest\trunning\n";
            commands.docker_output = "";
            var hints = new ResourceDiscovery(commands).scan(new GenericArray<Resource>());
            assert(hints.candidates.length == 5);
            for (uint i = 0; i < hints.candidates.length; i++) {
                assert(hints.candidates[i].guest_os == (i < 3 ? "windows" : ""));
                assert(hints.candidates[i].qmp_socket == "");
            }
        }

        public static void test_libvirt() {
            var commands = new DiscoveryCommands();
            commands.session_output = DOMAIN + " Domain with spaces; $data\n";
            commands.system_output = DOMAIN + "\tSystem domain\ninvalid bad-domain\n";
            var result = new ResourceDiscovery(commands).scan(new GenericArray<Resource>());
            assert(commands.calls == 4 && result.candidates.length == 2);
            assert(result.candidates[0].kind == "libvirt");
            assert(result.candidates[0].id == "qemu:///session:" + DOMAIN);
            assert(result.candidates[0].resource_id == DOMAIN);
            assert(result.candidates[0].name == "Domain with spaces; $data");
            assert(result.candidates[1].connection_uri == "qemu:///system");
            assert(result.sources[2].available && !result.sources[3].available);
        }

        public static void test_failures() {
            var commands = new DiscoveryCommands();
            commands.deny_podman = true;
            commands.missing_docker = true;
            commands.session_output = DOMAIN + " Available domain\n";
            var result = new ResourceDiscovery(commands).scan(new GenericArray<Resource>());
            assert(commands.calls == 4 && result.candidates.length == 1);
            assert(!result.sources[0].available && !result.sources[1].available);
            assert(result.sources[0].message == _("Runtime connection is unavailable or access was denied."));
            assert(result.sources[1].message == _("Runtime command is not installed or unavailable on the host."));
            assert(!result.sources[0].message.contains("secret-token"));
            assert(!result.sources[1].message.contains("secret-token"));
            assert(result.sources[2].available && result.sources[3].available);
        }

        public static void test_duplicates() {
            var commands = new DiscoveryCommands();
            commands.podman_output = CONTAINER_A + "\taliased\timage\trunning\n" +
                CONTAINER_B + "\tlegacy\timage\texited\n";
            commands.docker_output = CONTAINER_A + "\taliased\timage\trunning\n";
            commands.session_output = DOMAIN + " Existing domain\n";
            var existing = new GenericArray<Resource>();
            var legacy = new Resource();
            legacy.container_name = "legacy";
            existing.add(legacy);
            var domain = new Resource();
            domain.kind = "libvirt";
            domain.resource_id = DOMAIN;
            existing.add(domain);
            var result = new ResourceDiscovery(commands).scan(existing);
            assert(result.candidates.length == 1 && result.candidates[0].resource_id == CONTAINER_A);
            existing.add(result.candidates[0]);
            commands.calls = 0;
            result = new ResourceDiscovery(commands).scan(existing);
            assert(commands.calls == 4 && result.candidates.length == 0);
        }
    }
}
