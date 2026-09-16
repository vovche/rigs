/* main.vala — Test suite runner for Rigs */

using Rigs.Tests;

int main(string[] args) {
    Test.init(ref args);

    Test.add_func("/models/defaults", TestModels.test_vm_model_defaults);
    Test.add_func("/models/json_roundtrip", TestModels.test_vm_model_json_roundtrip);
    Test.add_func("/models/empty_json", TestModels.test_vm_model_empty_json);
    Test.add_func("/models/seed_default_vms", TestModels.test_seed_default_vms);

    Test.add_func("/drivers/registry_singleton", TestDrivers.test_registry_singleton);
    Test.add_func("/drivers/qemu_lookup", TestDrivers.test_qemu_driver_lookup);
    Test.add_func("/drivers/compose_lookup", TestDrivers.test_compose_driver_lookup);
    Test.add_func("/drivers/fallback_lookup", TestDrivers.test_fallback_driver_lookup);
    Test.add_func("/drivers/qemu_stopped_status", TestDrivers.test_qemu_stopped_status);
    Test.add_func("/drivers/compose_stopped_status", TestDrivers.test_compose_stopped_status);

    Test.add_func("/diagnostics/report", TestDiagnostics.test_diagnostics_report);

    return Test.run();
}
