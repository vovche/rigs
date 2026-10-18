# Work Packet: Portable onboarding and guest integration

## Goal
Remove personal VM defaults. On an empty installation, enumerate accessible
Podman/Docker containers and libvirt session/system domains, then let the user
choose what to register. Preserve existing configurations and custom commands.

## Target slices
- src/vm_model.vala + tests/test_models.vala: neutral read-only configuration
  loading, no seeding, stable runtime/resource_id/connection_uri persistence.
- src/discovery_dialog.vala + src/window.vala: asynchronous scan, per-source
  availability, explicit per-resource addition, first-run discovery, rescan.
- src/drivers/driver_registry.vala + tests/test_drivers.vala: register managed
  container/libvirt types, reject unknown driver types rather than selecting a
  potentially destructive fallback.
- src/drivers/compose_driver.vala + src/drivers/qemu_driver.vala: use shared
  HostCommand; no process-pattern kill fallback. Preserve explicit user scripts.
- src/guest_tools_dialog.vala + src/vm_card.vala: OS/channel configuration,
  diagnostic hints, official VirtIO download link; no false assertion that a
  driver is missing and no unrequested guest installation or VM restart.
- src/monitor.vala: integrate QMP/libvirt diagnosis on background worker.

Integration files explicitly allowed: src/add_dialog.vala, src/system_diagnostics.vala,
meson.build, src/meson.build, tests/main.vala, po/POTFILES.in, po/uk.po,
snap/snapcraft.yaml, README.md, ARCHITECTURE.md. Runtime enumeration/execution and
managed-driver contracts/tests live in the three adjacent discovery packets.

## Distribution contract
Native: current-user runtime commands. Flatpak: flatpak-spawn --host with
org.freedesktop.Flatpak permission. Strict Snap: only the connected Docker Snap
client/socket via declared docker and docker-executables plugs. Podman/libvirt
and custom host scripts require native/classic deployment or a future broker.
Do not present inaccessible inventories as empty successful discovery.
Standalone QEMU script monitoring requires host procfs; no raw process scan is
used to invent launch/stop commands. Discovery never performs lifecycle actions.

## Acceptance
- No personal paths, VM names or credentials in shipped source/defaults.
- Missing, empty and invalid config never recreates personal entries; invalid
  config is preserved and cannot be overwritten through registration.
- Four bounded inventory probes, identity deduplication, explicit import.
- Every imported resource has a matching driver and safe stable target.
- Native/Flatpak/Snap command preparation and diagnostics covered headlessly.
- Guest faults have distinct explanatory setup guidance.
- ./build.sh green, headless suite <1 second, separate live read-only smoke test.
- Flatpak/Snap package builds must be reported as unverified unless actually run.
