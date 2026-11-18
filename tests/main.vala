/* main.vala — Test suite runner for Rigs */

using Rigs.Tests;

int main(string[] args) {
    Test.init(ref args);

    Test.add_func("/models/defaults", TestModels.test_resource_defaults);
    Test.add_func("/guest-memory/windows-and-linux", TestGuestMemory.test_windows);
    Test.add_func("/guest-memory/invalid-and-stale", TestGuestMemory.test_invalid);
    Test.add_func("/guest-memory/qmp", TestGuestMemory.test_qmp);
    Test.add_func("/guest-memory/qmp-error", TestGuestMemory.test_qmp_error);
    Test.add_func("/guest-memory/states", TestGuestMemory.test_states);
    Test.add_func("/guest-memory/libvirt", TestGuestMemory.test_libvirt);
    Test.add_func("/models/json_roundtrip", TestModels.test_resource_json_roundtrip);
    Test.add_func("/models/empty_json", TestModels.test_resource_empty_json);
    Test.add_func("/models/empty_configuration", TestModels.test_empty_configuration);

    Test.add_func("/drivers/registry_singleton", TestDrivers.test_registry_singleton);
    Test.add_func("/drivers/qemu_lookup", TestDrivers.test_qemu_driver_lookup);
    Test.add_func("/drivers/compose_lookup", TestDrivers.test_compose_driver_lookup);
    Test.add_func("/drivers/fallback_lookup", TestDrivers.test_fallback_driver_lookup);
    Test.add_func("/drivers/qemu_stopped_status", TestDrivers.test_qemu_stopped_status);
    Test.add_func("/drivers/compose_stopped_status", TestDrivers.test_compose_stopped_status);
    Test.add_func("/drivers/compose_missing_container", TestDrivers.test_compose_missing_container_detection);
    Test.add_func("/drivers/qemu_start_spawns_process", TestDrivers.test_qemu_start_spawns_process);
    Test.add_func("/drivers/compose_start_spawns_process", TestDrivers.test_compose_start_spawns_process);
    Test.add_func("/drivers/mock_lifecycle", TestDrivers.test_mock_driver_lifecycle);

    Test.add_func("/diagnostics/report", TestDiagnostics.test_diagnostics_report);

    Test.add_func("/startup-diagnostics/empty", TestFailureRules.test_empty);
    Test.add_func("/startup-diagnostics/mount", TestFailureRules.test_mount);
    Test.add_func("/startup-diagnostics/port", TestFailureRules.test_port);
    Test.add_func("/startup-diagnostics/conflict", TestFailureRules.test_conflict);
    Test.add_func("/startup-diagnostics/kvm", TestFailureRules.test_kvm);
    Test.add_func("/startup-diagnostics/netns", TestFailureRules.test_netns);
    Test.add_func("/startup-diagnostics/oom", TestFailureRules.test_oom);
    Test.add_func("/startup-diagnostics/generic-and-limits", TestFailureRules.test_generic_and_limits);
    Test.add_func("/startup-diagnostics/diagnose-logs-fallback", TestFailureRules.test_diagnose_logs_fallback);
    Test.add_func("/startup-diagnostics/managed-start", TestFailureRules.test_managed_start);
    Test.add_func("/startup-diagnostics/model-issue", TestFailureRules.test_model_issue);

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
    Test.add_func("/managed-driver/container", TestRuntimeDrivers.test_container_status);
    Test.add_func("/managed-driver/libvirt", TestRuntimeDrivers.test_libvirt_status);
    Test.add_func("/managed-driver/invalid", TestRuntimeDrivers.test_invalid_targets);
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
    Test.add_func("/regressions/hmp-quoting", TestRegressions.test_hmp_quoting);
    Test.add_func("/regressions/hmp-send", TestRegressions.test_hmp_send);
    Test.add_func("/regressions/find-vm-pid", TestRegressions.test_find_vm_pid);
    Test.add_func("/regressions/metrics", TestRegressions.test_metrics);
    Test.add_func("/regressions/parse-mem", TestRegressions.test_parse_mem);
    Test.add_func("/regressions/capture-tail", TestRegressions.test_capture_tail);
    Test.add_func("/regressions/search-target-balanced", TestRegressions.test_search_target_balanced);
    Test.add_func("/regressions/hmp-command-output", TestRegressions.test_hmp_command_output);
    Test.add_func("/regressions/error-to-issue", TestRegressions.test_error_to_issue);
    Test.add_func("/regressions/qemu-start-failures", TestRegressions.test_qemu_start_failures);
    Test.add_func("/regressions/managed-start-failures", TestRegressions.test_managed_start_failures);
    Test.add_func("/regressions/save-failure-reported", TestRegressions.test_save_failure_reported);
    Test.add_func("/presets/qemu-script", TestResourcePresets.test_qemu_script);
    Test.add_func("/presets/compose", TestResourcePresets.test_compose);
    Test.add_func("/presets/validate", TestResourcePresets.test_validate);
    return Test.run();
}
