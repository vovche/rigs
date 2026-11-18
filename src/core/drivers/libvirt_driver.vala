using GLib.Intl;

/* libvirt_driver.vala — a libvirt domain on qemu:///session or qemu:///system,
 * addressed by UUID (resource_id). Uses `virsh` and `virt-viewer` with fixed argv. */
namespace Rigs {
    public class LibvirtDriver : Object, Driver {
        private HostCommand commands;
        // Milliseconds to wait before checking whether a started domain died at once.
        public uint settle_ms = 2000;

        public ResourceKind kind { get { return ResourceKind.LIBVIRT; } }

        public LibvirtDriver(HostCommand? commands = null) {
            this.commands = commands ?? new HostCommand();
        }

        public static bool valid_target(Resource resource) {
            return (resource.connection_uri == "qemu:///session" || resource.connection_uri == "qemu:///system") &&
                Regex.match_simple("^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$", resource.resource_id);
        }

        // Public for deterministic lifecycle contract tests without starting real resources.
        public string[] lifecycle_argv(Resource resource, bool starting) {
            if (!valid_target(resource)) return {};
            return { "virsh", "--connect", resource.connection_uri, starting ? "start" : "shutdown", resource.resource_id };
        }

        public string[] console_argv(Resource resource) {
            if (!valid_target(resource)) return {};
            return { "virt-viewer", "--connect", resource.connection_uri, resource.resource_id };
        }

        private ResourceIssue invalid_target() {
            return ResourceIssue.unsupported(_("Only local libvirt domains (qemu:///session or qemu:///system) with a UUID are supported."));
        }

        public ResourceIssue? start(Resource resource) {
            string[] argv = lifecycle_argv(resource, true);
            if (argv.length == 0) return invalid_target();
            try {
                var result = commands.run(argv, null, 30000);
                if (result.exit_status != 0) return FailureRules.diagnose(result, resource.guest_os);
                if (settle_ms > 0) Thread.usleep(settle_ms * 1000);
                return exited_after_start(resource);
            } catch (Error e) {
                return ResourceIssue.from_error(e);
            }
        }

        // `virsh start` succeeds before QEMU has fully come up; a domain that died at once is "shut off"/"crashed".
        private ResourceIssue? exited_after_start(Resource resource) throws Error {
            var state = commands.run({ "virsh", "--connect", resource.connection_uri, "domstate", "--reason", resource.resource_id });
            string text = state.output.strip();
            if (state.exit_status != 0 || !(text.has_prefix("shut off") || text.has_prefix("crashed"))) return null;
            return ResourceIssue.not_running(text,
                "virsh --connect %s dominfo %s".printf(resource.connection_uri, resource.resource_id));
        }

        public ResourceIssue? stop(Resource resource) {
            string[] argv = lifecycle_argv(resource, false);
            if (argv.length == 0) return invalid_target();
            return FailureRules.check_command(commands, argv, null, 35000);
        }

        public ResourceIssue? open_console(Resource resource) {
            string[] argv = console_argv(resource);
            if (argv.length == 0) return invalid_target();
            return FailureRules.check_command(commands, argv, null);
        }

        public ResourceIssue? insert_iso(Resource resource, string iso_path) {
            return ResourceIssue.unsupported(_("Change libvirt media with virt-manager or virsh change-media."));
        }

        public ResourceIssue? eject_iso(Resource resource) {
            return insert_iso(resource, "");
        }

        public ResourceStatus check_status(Resource resource) {
            ResourceStatus status = ResourceStatus();
            status.ram_str = "—";
            if (!valid_target(resource)) return status;
            try {
                // HostCommand supplies LC_ALL=C so virsh field names are stable.
                var info = commands.run({ "virsh", "--connect", resource.connection_uri, "dominfo", resource.resource_id });
                if (info.exit_status != 0) return status;
                string state = "";
                string memory = "";
                foreach (string line in info.output.split("\n")) {
                    int colon = line.index_of(":");
                    if (colon < 0) continue;
                    string key = line.substring(0, colon).strip();
                    string value = line.substring(colon + 1).strip();
                    if (key == "State") state = value;
                    if (key == "Used memory") memory = value;
                }
                switch (state) {
                    case "running": case "paused": case "idle": case "in shutdown": case "pmsuspended":
                        status.running = true;
                        break;
                    case "shut off": case "crashed":
                        break;
                    default:
                        return status;
                }
                status.status_available = true;
                if (memory.length > 0) status.ram_str = memory;
            } catch (Error e) {
                // Preserve authoritative running state when only statistics are inaccessible.
            }
            return status;
        }
    }
}
