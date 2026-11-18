/* mock_driver.vala — In-memory Mock Driver for deterministic testing */

using Rigs;

namespace Rigs.Tests {

    public class MockDriver : Object, Driver {
        public ResourceKind mock_kind = ResourceKind.QEMU;
        public ResourceKind kind { get { return mock_kind; } }
        // Returned by every operation; null = success.
        public ResourceIssue? next_issue = null;

        public GenericArray<string> started = new GenericArray<string>();
        public GenericArray<string> stopped = new GenericArray<string>();
        public GenericArray<string> connected = new GenericArray<string>();
        public HashTable<string, string> inserted_isos = new HashTable<string, string>(str_hash, str_equal);
        public GenericArray<string> ejected_isos = new GenericArray<string>();
        public ResourceStatus mock_status;

        public MockDriver(ResourceKind kind = ResourceKind.QEMU) {
            this.mock_kind = kind;
            this.mock_status = ResourceStatus();
            this.mock_status.running = false;
            this.mock_status.cpu_pct = 0.0;
            this.mock_status.ram_str = "0 MB";
        }

        public ResourceIssue? start(Resource resource) {
            started.add(resource.id);
            return next_issue;
        }

        public ResourceIssue? stop(Resource resource) {
            stopped.add(resource.id);
            return next_issue;
        }

        public ResourceIssue? open_console(Resource resource) {
            connected.add(resource.id);
            return next_issue;
        }

        public ResourceStatus check_status(Resource resource) {
            return mock_status;
        }

        public ResourceIssue? insert_iso(Resource resource, string iso_path) {
            inserted_isos.insert(resource.id, iso_path);
            return next_issue;
        }

        public ResourceIssue? eject_iso(Resource resource) {
            ejected_isos.add(resource.id);
            return next_issue;
        }

        public void reset() {
            started = new GenericArray<string>();
            stopped = new GenericArray<string>();
            connected = new GenericArray<string>();
            inserted_isos.remove_all();
            ejected_isos = new GenericArray<string>();
        }
    }
}
