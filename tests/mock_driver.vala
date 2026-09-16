/* mock_driver.vala — In-memory Mock Driver for deterministic testing */

using Rigs;

namespace Rigs.Tests {

    public class MockDriver : Object, Driver {
        public string custom_vm_type { get; set; default = "mock"; }
        public string vm_type { get { return custom_vm_type; } }

        public GenericArray<string> started_vms = new GenericArray<string>();
        public GenericArray<string> stopped_vms = new GenericArray<string>();
        public GenericArray<string> connected_vms = new GenericArray<string>();
        public HashTable<string, string> inserted_isos = new HashTable<string, string>(str_hash, str_equal);
        public GenericArray<string> ejected_isos = new GenericArray<string>();
        public VmStatus mock_status;

        public MockDriver(string type_name = "mock") {
            this.custom_vm_type = type_name;
            this.mock_status = VmStatus();
            this.mock_status.running = false;
            this.mock_status.cpu_pct = 0.0;
            this.mock_status.ram_str = "0 MB";
        }

        public void start(VmModel vm) {
            started_vms.add(vm.id);
        }

        public void stop(VmModel vm) {
            stopped_vms.add(vm.id);
        }

        public void connect_vm(VmModel vm) {
            connected_vms.add(vm.id);
        }

        public VmStatus check_status(VmModel vm) {
            return mock_status;
        }

        public void insert_iso(VmModel vm, string iso_path) {
            inserted_isos.insert(vm.id, iso_path);
        }

        public void eject_iso(VmModel vm) {
            ejected_isos.add(vm.id);
        }

        public void reset() {
            started_vms = new GenericArray<string>();
            stopped_vms = new GenericArray<string>();
            connected_vms = new GenericArray<string>();
            inserted_isos.remove_all();
            ejected_isos = new GenericArray<string>();
        }
    }
}
