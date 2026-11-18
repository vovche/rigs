/* driver_registry.vala — Registry and factory for VM drivers */

namespace Rigs {

    public class DriverRegistry : Object {
        private static DriverRegistry instance;
        private HashTable<string, Driver> drivers;

        public static DriverRegistry get_default() {
            if (instance == null) {
                instance = new DriverRegistry();
            }
            return instance;
        }

        private DriverRegistry() {
            drivers = new HashTable<string, Driver>(str_hash, str_equal);
            register_driver(new ScriptedQemuDriver());
            register_driver(new ComposeDriver());
            register_driver(new ManagedDriver("container"));
            register_driver(new ManagedDriver("libvirt"));
        }

        public void register_driver(Driver driver) {
            drivers.insert(driver.kind, driver);
        }

        public Driver? get_driver(string kind) {
            Driver? drv = drivers.lookup(kind);
            if (drv == null) {
                return null;
            }
            return drv;
        }
    }
}
