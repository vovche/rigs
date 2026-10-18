/* main.vala — Test suite runner for Rigs */

using Rigs.Tests;

int main(string[] args) {
    Test.init(ref args);

    Test.add_func("/models/defaults", TestModels.test_vm_model_defaults);
    Test.add_func("/guest-memory/windows-and-linux", TestGuestMemory.test_windows);
    Test.add_func("/guest-memory/invalid-and-stale", TestGuestMemory.test_invalid);
    Test.add_func("/guest-memory/qmp", TestGuestMemory.test_qmp);
    Test.add_func("/guest-memory/qmp-error", TestGuestMemory.test_qmp_error);
    Test.add_func("/guest-memory/states", TestGuestMemory.test_states);
    Test.add_func("/guest-memory/libvirt", TestGuestMemory.test_libvirt);
    Test.add_func("/models/json_roundtrip", TestModels.test_vm_model_json_roundtrip);
    Test.add_func("/models/empty_json", TestModels.test_vm_model_empty_json);
    Test.add_func("/models/empty_configuration", TestModels.test_empty_configuration);

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

    Test.add_func("/host-command/prepare", TestHostCommand.test_prepare);
    Test.add_func("/host-command/native", TestHostCommand.test_native);
    Test.add_func("/host-command/timeout", TestHostCommand.test_timeout);
    Test.add_func("/discovery/containers", TestDiscovery.test_containers);
    Test.add_func("/discovery/libvirt", TestDiscovery.test_libvirt);
    Test.add_func("/discovery/failures", TestDiscovery.test_failures);
    Test.add_func("/discovery/duplicates", TestDiscovery.test_duplicates);
    Test.add_func("/managed-driver/container", TestManagedDriver.test_container_status);
    Test.add_func("/managed-driver/libvirt", TestManagedDriver.test_libvirt_status);
    Test.add_func("/managed-driver/invalid", TestManagedDriver.test_invalid_targets);
    Test.add_func("/guest-agent/libvirt", TestGuestAgent.test_libvirt);
    Test.add_func("/guest-agent/socket", TestGuestAgent.test_socket);
    Test.add_func("/guest-agent/errors", TestGuestAgent.test_errors);
    Test.add_func("/guest-media/qmp", TestGuestMedia.test_qmp_media);
    Test.add_func("/guest-media/libvirt", TestGuestMedia.test_libvirt_media);
    Test.add_func("/guest-media/invalid", TestGuestMedia.test_invalid_targets);
    Test.add_func("/guest-media/container-mounts", TestGuestMedia.test_container_mounts);
    Test.add_func("/guest-media/iso", TestGuestMedia.test_iso_validation);
    Test.add_func("/guest-packages/download", TestGuestToolsPackages.test_download);
    Test.add_func("/guest-packages/local", TestGuestToolsPackages.test_local_files);
    Test.add_func("/guest-install/probe", TestWindowsGuestInstaller.test_probe);
    Test.add_func("/guest-install/install", TestWindowsGuestInstaller.test_install);
    Test.add_func("/guest-install/failures", TestWindowsGuestInstaller.test_failures);
    Test.add_func("/guest-install/scripts", TestWindowsGuestInstaller.test_scripts);
    Test.add_func("/guest-install/resume", TestWindowsGuestInstaller.test_resume);
    return Test.run();
}
