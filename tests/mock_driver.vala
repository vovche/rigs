/* mock_driver.vala — In-memory Mock Driver for deterministic testing */

using Rigs;

namespace Rigs.Tests {

    public class MockDriver : Object, Driver {
        public string custom_kind { get; set; default = "mock"; }
        public string kind { get { return custom_kind; } }

        public GenericArray<string> started = new GenericArray<string>();
        public GenericArray<string> stopped = new GenericArray<string>();
        public GenericArray<string> connected = new GenericArray<string>();
        public HashTable<string, string> inserted_isos = new HashTable<string, string>(str_hash, str_equal);
        public GenericArray<string> ejected_isos = new GenericArray<string>();
        public ResourceStatus mock_status;

        public MockDriver(string type_name = "mock") {
            this.custom_kind = type_name;
            this.mock_status = ResourceStatus();
            this.mock_status.running = false;
            this.mock_status.cpu_pct = 0.0;
            this.mock_status.ram_str = "0 MB";
        }

        public void start(Resource resource) {
            started.add(resource.id);
        }

        public void stop(Resource resource) {
            stopped.add(resource.id);
        }

        public void open_console(Resource resource) {
            connected.add(resource.id);
        }

        public ResourceStatus check_status(Resource resource) {
            return mock_status;
        }

        public void insert_iso(Resource resource, string iso_path) {
            inserted_isos.insert(resource.id, iso_path);
        }

        public void eject_iso(Resource resource) {
            ejected_isos.add(resource.id);
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
