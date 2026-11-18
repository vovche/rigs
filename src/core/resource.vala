/* resource.vala — one managed thing (VM, container, compose project) and its live status. */

namespace Rigs {
    // What a resource is; selects its Driver. Stored in vms.json as "type".
    public enum ResourceKind {
        QEMU,       // a user script that runs QEMU (start_cmd / run-vm.sh)
        COMPOSE,    // a compose project directory (podman/docker compose)
        CONTAINER,  // one existing container, addressed by its ID
        LIBVIRT;    // a libvirt domain, addressed by URI + UUID

        public string to_id() {
            switch (this) {
                case ResourceKind.QEMU: return "qemu";
                case ResourceKind.CONTAINER: return "container";
                case ResourceKind.LIBVIRT: return "libvirt";
                default: return "compose";
            }
        }

        public static bool try_parse(string id, out ResourceKind kind) {
            foreach (var candidate in new ResourceKind[] { QEMU, COMPOSE, CONTAINER, LIBVIRT }) {
                if (candidate.to_id() == id) { kind = candidate; return true; }
            }
            kind = ResourceKind.COMPOSE;
            return false;
        }
    }

    // Container engine CLI. Stored in vms.json as "runtime"; command() is argv[0].
    public enum ContainerRuntime {
        PODMAN,
        DOCKER;

        public string command() {
            return this == ContainerRuntime.DOCKER ? "docker" : "podman";
        }

        public static bool try_parse(string id, out ContainerRuntime runtime) {
            runtime = id == "docker" ? ContainerRuntime.DOCKER : ContainerRuntime.PODMAN;
            return id == "docker" || id == "podman";
        }
    }


    public class Resource : Object {
        public string id { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string subtitle { get; set; default = ""; }
        public ResourceKind kind { get; set; default = ResourceKind.COMPOSE; }
        public string icon { get; set; default = "computer-symbolic"; }
        public string dir { get; set; default = ""; }
        public string start_cmd { get; set; default = ""; }
        public string stop_cmd { get; set; default = ""; }
        public string connect_cmd { get; set; default = ""; }
        public string details { get; set; default = ""; }
        public string container_name { get; set; default = ""; }
        public string process_match { get; set; default = ""; }
        public string monitor_socket { get; set; default = ""; }
        public string attached_iso { get; set; default = ""; }
        public string qmp_socket { get; set; default = ""; }
        public string guest_agent_socket { get; set; default = ""; }
        public string guest_os { get; set; default = ""; }
        public ContainerRuntime runtime { get; set; default = ContainerRuntime.PODMAN; }
        public string resource_id { get; set; default = ""; }
        public string connection_uri { get; set; default = "qemu:///session"; }

        // Runtime-only (never persisted): outcome of the most recent failed start.
        public ResourceIssue? last_issue { get; set; default = null; }
        public signal void issue_raised(ResourceIssue issue);

        public static Resource from_json_node(Json.Node node) {
            var model = new Resource();
            if (node.get_node_type() != Json.NodeType.OBJECT) {
                return model;
            }
            unowned Json.Object obj = node.get_object();

            if (obj.has_member("id")) model.id = obj.get_string_member("id");
            if (obj.has_member("name")) model.name = obj.get_string_member("name");
            if (obj.has_member("subtitle")) model.subtitle = obj.get_string_member("subtitle");
            // Unknown "type"/"runtime" values are rejected earlier by ResourceStore.valid_entry.
            ResourceKind kind = ResourceKind.COMPOSE;
            if (obj.has_member("type") && ResourceKind.try_parse(obj.get_string_member("type"), out kind)) model.kind = kind;
            if (obj.has_member("icon")) model.icon = obj.get_string_member("icon");
            if (obj.has_member("dir")) model.dir = obj.get_string_member("dir");
            if (obj.has_member("start_cmd")) model.start_cmd = obj.get_string_member("start_cmd");
            if (obj.has_member("stop_cmd")) model.stop_cmd = obj.get_string_member("stop_cmd");
            if (obj.has_member("connect_cmd")) model.connect_cmd = obj.get_string_member("connect_cmd");
            if (obj.has_member("details")) model.details = obj.get_string_member("details");
            if (obj.has_member("container_name")) model.container_name = obj.get_string_member("container_name");
            if (obj.has_member("process_name")) model.process_match = obj.get_string_member("process_name");
            if (obj.has_member("monitor_socket")) model.monitor_socket = obj.get_string_member("monitor_socket");
            if (obj.has_member("attached_iso")) model.attached_iso = obj.get_string_member("attached_iso");
            if (obj.has_member("qmp_socket")) model.qmp_socket = obj.get_string_member("qmp_socket");
            if (obj.has_member("guest_agent_socket")) model.guest_agent_socket = obj.get_string_member("guest_agent_socket");
            if (obj.has_member("guest_os")) model.guest_os = obj.get_string_member("guest_os");

            ContainerRuntime runtime = ContainerRuntime.PODMAN;
            if (obj.has_member("runtime") && ContainerRuntime.try_parse(obj.get_string_member("runtime"), out runtime))
                model.runtime = runtime;
            if (obj.has_member("resource_id")) model.resource_id = obj.get_string_member("resource_id");
            if (obj.has_member("connection_uri")) model.connection_uri = obj.get_string_member("connection_uri");
            return model;
        }

        public Json.Object to_json_object() {
            var obj = new Json.Object();
            obj.set_string_member("id", id);
            obj.set_string_member("name", name);
            obj.set_string_member("subtitle", subtitle);
            obj.set_string_member("type", kind.to_id());
            obj.set_string_member("icon", icon);
            obj.set_string_member("dir", dir);
            obj.set_string_member("start_cmd", start_cmd);
            obj.set_string_member("stop_cmd", stop_cmd);
            obj.set_string_member("connect_cmd", connect_cmd);
            obj.set_string_member("details", details);
            if (container_name.length > 0) obj.set_string_member("container_name", container_name);
            if (process_match.length > 0) obj.set_string_member("process_name", process_match);
            if (monitor_socket.length > 0) obj.set_string_member("monitor_socket", monitor_socket);
            if (attached_iso.length > 0) obj.set_string_member("attached_iso", attached_iso);
            if (qmp_socket.length > 0) obj.set_string_member("qmp_socket", qmp_socket);
            if (guest_agent_socket.length > 0) obj.set_string_member("guest_agent_socket", guest_agent_socket);
            if (guest_os.length > 0) obj.set_string_member("guest_os", guest_os);
            obj.set_string_member("runtime", runtime.command());
            if (resource_id.length > 0) obj.set_string_member("resource_id", resource_id);
            if (kind == ResourceKind.LIBVIRT) obj.set_string_member("connection_uri", connection_uri);
            return obj;
        }
    }

    public struct ResourceStatus {
        public bool running;
        public bool status_available;
        public double cpu_pct;
        public string ram_str;
        public double ram_pct;
        public bool guest_ram_valid;
        public string guest_ram_str;
        public double guest_ram_pct;
        public GuestMemoryState guest_memory_state;
    }

    public struct HostStatus {
        public double cpu_pct;
        public double ram_used_gb;
        public double ram_total_gb;
        public double ram_pct;
    }

}
