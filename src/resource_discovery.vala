using GLib.Intl;

namespace Rigs {
    public class DiscoverySource : Object {
        public string name { get; set; default = ""; }
        public bool available { get; set; default = false; }
        public string message { get; set; default = ""; }

        public DiscoverySource(string name = "", bool available = false, string message = "") {
            this.name = name;
            this.available = available;
            this.message = message;
        }
    }

    public class DiscoveryResult : Object {
        public GenericArray<VmModel> candidates = new GenericArray<VmModel>();
        public GenericArray<DiscoverySource> sources = new GenericArray<DiscoverySource>();
    }

    // Discovery only enumerates runtime inventories; it never changes their state.
    public class ResourceDiscovery : Object {
        private HostCommand commands;

        public ResourceDiscovery(HostCommand? commands = null) {
            this.commands = commands ?? new HostCommand();
        }

        private bool is_windows_vm_image(string image) {
            // Only recognize the Windows VM image repositories, not container names
            // or arbitrary images that happen to contain the word "windows".
            string repository = image.split("@")[0];
            int slash = repository.last_index_of_char('/');
            int colon = repository.last_index_of_char(':');
            if (colon > slash) repository = repository.substring(0, colon);
            return repository == "dockur/windows" || repository == "dockurr/windows" ||
                repository.has_suffix("/dockur/windows") || repository.has_suffix("/dockurr/windows");
        }

        private string failure_message(string detail) {
            if (commands.mode == "snap-restricted")
                return _("Connect the Docker interfaces in a supported Snap package to discover Docker resources. Podman and libvirt require a native package, classic Snap, or host broker.");
            string lower = detail.down();
            if (commands.mode.has_prefix("snap") &&
                (lower.contains("not supported") || lower.contains("supports only the connected docker")))
                return _("This Snap supports Docker through connected Docker interfaces. Podman and libvirt require a native package, classic Snap, or host broker.");
            if (lower.contains("deadline") || lower.contains("timed out"))
                return _("Runtime inventory timed out. Check the runtime connection and try again.");
            if (lower.contains("not found") || lower.contains("no such file"))
                return _("Runtime command is not installed or unavailable on the host.");
            if (lower.contains("permission") || lower.contains("denied") ||
                lower.contains("connect") || lower.contains("socket") || lower.contains("authorization"))
                return _("Runtime connection is unavailable or access was denied.");
            return _("Runtime discovery failed. Check host access and runtime availability.");
        }

        public DiscoveryResult scan(GenericArray<VmModel> existing) {
            var result = new DiscoveryResult();
            var container_ids = new HashTable<string, bool>(str_hash, str_equal);
            var legacy_names = new HashTable<string, bool>(str_hash, str_equal);
            var domains = new HashTable<string, bool>(str_hash, str_equal);
            for (uint i = 0; i < existing.length; i++) {
                var vm = existing[i];
                if (vm.vm_type == "container" || vm.vm_type == "compose") {
                    if (vm.resource_id.length > 0) container_ids.insert(vm.resource_id.down(), true);
                    if (vm.vm_type == "compose" && vm.container_name.length > 0)
                        legacy_names.insert(vm.runtime + ":" + vm.container_name, true);
                } else if (vm.vm_type == "libvirt") {
                    domains.insert(vm.connection_uri + ":" + vm.resource_id.down(), true);
                }
            }
            foreach (string engine in new string[] { "podman", "docker" }) {
                var source = new DiscoverySource(engine);
                result.sources.add(source);
                try {
                    var response = commands.run({ engine, "ps", "--all", "--no-trunc", "--format",
                        "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.State}}" });
                    if (response.exit_status != 0) {
                        source.message = failure_message(response.error_output);
                        continue;
                    }
                    bool malformed = false;
                    foreach (string line in response.output.split("\n")) {
                        if (line.strip().length == 0) continue;
                        string[] fields = line.split("\t");
                        if (fields.length != 4 || !Regex.match_simple("^[0-9a-fA-F]{12,64}$", fields[0]) ||
                            fields[1].strip().length == 0) {
                            malformed = true;
                            continue;
                        }
                        string identity = fields[0].down();
                        if (container_ids.contains(identity)) continue;
                        container_ids.insert(identity, true);
                        if (legacy_names.contains(engine + ":" + fields[1])) continue;
                        var vm = new VmModel();
                        vm.id = engine + ":" + identity;
                        vm.name = fields[1];
                        vm.vm_type = "container";
                        vm.runtime = engine;
                        vm.resource_id = identity;
                        vm.container_name = fields[1];
                        vm.subtitle = engine + " • " + fields[2];
                        vm.details = fields[3];
                        vm.icon = "network-server-symbolic";
                        if (is_windows_vm_image(fields[2])) vm.guest_os = "windows";
                        result.candidates.add(vm);
                    }
                    source.available = !malformed;
                    source.message = malformed ? _("Runtime returned malformed inventory data; some resources were skipped.") :
                        _("Runtime inventory is available.");
                } catch (Error e) {
                    source.message = failure_message(e.message);
                }
            }
            foreach (string uri in new string[] { "qemu:///session", "qemu:///system" }) {
                var source = new DiscoverySource("libvirt " + uri);
                result.sources.add(source);
                try {
                    var response = commands.run({ "virsh", "--readonly", "--connect", uri, "list", "--all", "--uuid", "--name" });
                    if (response.exit_status != 0) {
                        source.message = failure_message(response.error_output);
                        continue;
                    }
                    bool malformed = false;
                    foreach (string raw_line in response.output.split("\n")) {
                        string line = raw_line.strip();
                        if (line.length == 0) continue;
                        if (!Regex.match_simple("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[ \\t]+.+$", line)) {
                            malformed = true;
                            continue;
                        }
                        string uuid = line.substring(0, 36).down();
                        string identity = uri + ":" + uuid;
                        if (domains.contains(identity)) continue;
                        domains.insert(identity, true);
                        var vm = new VmModel();
                        vm.id = identity;
                        vm.name = line.substring(36).strip();
                        vm.vm_type = "libvirt";
                        vm.resource_id = uuid;
                        vm.connection_uri = uri;
                        vm.subtitle = "libvirt • " + uri;
                        vm.icon = "computer-symbolic";
                        result.candidates.add(vm);
                    }
                    source.available = !malformed;
                    source.message = malformed ? _("Runtime returned malformed inventory data; some resources were skipped.") :
                        _("Runtime inventory is available.");
                } catch (Error e) {
                    source.message = failure_message(e.message);
                }
            }
            return result;
        }
    }
}
