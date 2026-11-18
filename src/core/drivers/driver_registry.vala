/* driver_registry.vala — maps each ResourceKind to its Driver. */
namespace Rigs {
    public class DriverRegistry : Object {
        private static DriverRegistry instance;
        private HashTable<string, Driver> drivers = new HashTable<string, Driver>(str_hash, str_equal);

        public static DriverRegistry get_default() {
            if (instance == null) instance = new DriverRegistry.with_defaults();
            return instance;
        }

        // Empty registry for tests; register fakes with register_driver().
        public DriverRegistry() { }

        public DriverRegistry.with_defaults() {
            register_driver(new ScriptedQemuDriver());
            register_driver(new ComposeDriver());
            register_driver(new ContainerDriver());
            register_driver(new LibvirtDriver());
        }

        public void register_driver(Driver driver) {
            drivers.insert(driver.kind.to_id(), driver);
        }

        public Driver? get_driver(ResourceKind kind) {
            return drivers.lookup(kind.to_id());
        }
    }
}
