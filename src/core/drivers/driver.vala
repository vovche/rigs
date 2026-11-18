/* driver.vala — Abstract interface for hypervisor and container drivers */

namespace Rigs {

    public interface Driver : Object {
        public abstract string kind { get; }
        public abstract void start(Resource resource);
        public abstract void stop(Resource resource);
        public abstract void open_console(Resource resource);
        public abstract ResourceStatus check_status(Resource resource);
        public abstract void insert_iso(Resource resource, string iso_path);
        public abstract void eject_iso(Resource resource);
    }
}
