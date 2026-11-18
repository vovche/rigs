# Work Packet: Host command execution

> **Historical packet.** Flatpak delivery was dropped on 2026-11-19; ignore its Flatpak parts (see README "Flatpak: not supported").

## Targets (owned exclusively by worker)
- src/host_command.vala
- tests/test_host_command.vala

## Contract
Namespace Rigs. `CommandResult : Object` with public fields `string output`,
`string error_output`, `int exit_status`; constructor `(string output = "",
string error_output = "", int exit_status = 0)`.
`HostCommand : Object` has virtual methods:
`CommandResult run(string[] argv, string? directory = null, uint timeout_ms = 3000) throws Error`
`void launch(string[] argv, string? directory = null) throws Error`.
`public string mode { get; }` values native, flatpak, snap-classic, snap-restricted.
Optional constructor `HostCommand(string? mode_override = null)` for tests.
`public string[] prepare(string[] argv, string? directory = null) throws Error`
returns actual executable argv. Native/classic preserve argv. Flatpak prefix
`flatpak-spawn --host --watch-bus` plus `--directory=<directory>` when supplied.
Native cwd is set on launcher; Flatpak host cwd passed only through prefix.
Do not quote or shell-concatenate argv. Reject empty argv. Native commands run
with LC_ALL=C for stable output. Flatpak pass `--env=LC_ALL=C`.
Detect Flatpak via /.flatpak-info or FLATPAK_ID. Detect Snap via SNAP; determine
classic only from SNAP/meta/snap.yaml line `confinement: classic`. Unknown Snap
is restricted. Restricted commands throw NOT_SUPPORTED with actionable text;
never silently execute host-dependent commands within the sandbox.
Bound synchronous execution using Cancellable + watchdog thread (headless,
no main loop), cancel communication and force-exit only its child on deadline.
Close pipes/reap process; join watchdog immediately on normal completion.
`launch` starts detached by GLib without waiting (for lifecycle scripts/viewers).

## Tests
Class Rigs.Tests.TestHostCommand methods test_prepare, test_native, test_timeout.
Verify exact argv (including paths with spaces), Flatpak cwd and environment,
strict Snap rejection, native printf with shell metacharacters literal, nonzero
exit preserves stderr, /bin/sleep timeout ~30ms. No VM/config/D-Bus access.
Parent owns build files/test registrations. Tell parent when ready to compile.
