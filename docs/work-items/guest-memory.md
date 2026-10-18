# Work Packet: Guest RAM telemetry

## Goal
Display guest RAM separately from host/container memory, using QMP balloon
statistics. Tiny10 already has BalloonService; its QEMU launch needs an
explicit balloon0 device and a QMP socket. Do not enable automatic resizing.

## Slices and boundaries
1. `src/vm_model.vala`, `tests/test_models.vala`: persist optional `qmp_socket`
   and `guest_os` strings (default empty); add guest RAM validity, formatted
   value and percent to VmStatus. Old configurations remain valid.
2. `src/guest_memory.vala`, `tests/test_guest_memory.vala`: bounded Unix QMP
   client plus validated conversion. `GuestMemory.read(string socket_path,
   bool windows)` returns nullable GuestMemory; `from_stats(Json.Object data,
   bool windows, int64 now)` validates timestamps and integer counters.
   Windows uses stat-free-memory (VirtIO maps GlobalMemoryStatusEx available
   physical RAM); Linux uses stat-available-memory. No total-minus-free
   fallback for Linux. Reject missing, -1, zero total, out-of-range, stale
   (>15s), zero timestamp and future (>5s) readings. Preserve valid 0% use.
3. `src/monitor.vala`, `src/vm_card.vala`: query configured running VMs on the
   existing background worker. Separate guest RAM and host RAM rows; show an
   explicit unavailable state when guest data cannot be read, never host
   consumption as guest use.

Explicit integration files: `src/meson.build`, `meson.build`, `tests/main.vala`,
`po/uk.po`, `README.md`, `ARCHITECTURE.md`.

## Verification
Headless fixture tests and a local fake Unix QMP peer must cover valid Windows
45%, Linux available-memory semantics, invalid/stale stats, QMP events/errors,
and disconnected endpoints. Tests must not access user VMs/configurations.
Run `./build.sh` and then a separate authorized live probe of Tiny10. Compare
with Windows counters, allowing for different sampling times. Live VM restart
is separate from unit tests and requires the user's answer about unsaved work.
