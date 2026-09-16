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
    Test.add_func("/drivers/qemu_start_spawns_process", TestDrivers.test_qemu_start_spawns_process);
    Test.add_func("/drivers/compose_start_spawns_process", TestDrivers.test_compose_start_spawns_process);
    Test.add_func("/drivers/mock_lifecycle", TestDrivers.test_mock_driver_lifecycle);

    Test.add_func("/diagnostics/report", TestDiagnostics.test_diagnostics_report);

    Test.add_func("/search/initial_by_name", TestSearchProvider.test_initial_search_by_name);
    Test.add_func("/search/initial_by_port_and_type", TestSearchProvider.test_initial_search_by_port_and_type);
    Test.add_func("/search/subsearch", TestSearchProvider.test_subsearch);
    Test.add_func("/search/result_metas", TestSearchProvider.test_result_metas);

    return Test.run();
}
