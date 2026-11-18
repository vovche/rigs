/* driver.vala — Abstract interface for hypervisor and container drivers */

namespace Rigs {

    public interface Driver : Object {
        public abstract string vm_type { get; }
        public abstract void start(VmModel vm);
        public abstract void stop(VmModel vm);
        public abstract void connect_vm(VmModel vm);
        public abstract VmStatus check_status(VmModel vm);
        public abstract void insert_iso(VmModel vm, string iso_path);
        public abstract void eject_iso(VmModel vm);
    }
}
