# Work Packet: Guest integration diagnostics

## Targets
- src/guest_memory.vala
- tests/test_guest_memory.vala

## Contract
Keep existing GuestMemory.read/from_stats behavior for callers. Add enum
Rigs.GuestMemoryState { NOT_CONFIGURED, CONNECTION_UNAVAILABLE, DEVICE_MISSING,
GUEST_NOT_REPORTING, STALE, UNSUPPORTED, READY } and class GuestMemoryCheck : Object
public fields `GuestMemoryState state` and `GuestMemory? memory`, constructor
`GuestMemoryCheck(GuestMemoryState state, GuestMemory? memory=null)`.
Add GuestMemory.check(string socket_path,bool windows) returns GuestMemoryCheck.
Empty path NOT_CONFIGURED; socket/protocol errors CONNECTION_UNAVAILABLE;
after capabilities issue qom-list at /machine/peripheral and verify child
balloon0 exists (array of objects with string name). Absent DEVICE_MISSING.
Then qom-set polling=5; qom-get stats. timestamp0 GUEST_NOT_REPORTING; timestamp
>15s old STALE; invalid/missing counters UNSUPPORTED; valid READY and memory.
Do not assert drivers missing merely because no metrics. `read` wraps check.memory.
Bound QMP frames and deadlines preserved. Add fake peer tests for states and
update current fake peer protocol to include qom-list. Retain headless <1s tests.

Also add `check_libvirt(string uri,string uuid,bool windows,HostCommand? commands=null)`.
Validate local session/system URI and UUID before commands. Use injected HostCommand
(run argv/cwd/timeout returns CommandResult output,error_output,exit_status).
Run virsh --connect URI dommemstat UUID --period 5 --live to enable polling,
then virsh --connect URI dommemstat UUID. This never resizes memory. Translate
counters: available -> total, unused -> Windows available physical RAM, usable
-> Linux MemAvailable, last_update -> timestamp. Feed same validation/mapping.
Setter/connection failure CONNECTION_UNAVAILABLE; no timestamp/zero timestamp
GUEST_NOT_REPORTING, stale STALE, unsupported counters UNSUPPORTED. Do not use
actual or rss as guest used. Fake HostCommand tests for Windows/Linux and failed
connections, record no resize/lifecycle calls. Parent adds HostCommand build dep
(already included), enum field in VmStatus, UI diagnosis messages and setup form.
Notify parent when ready, no other files touched. No user VM operations/tests.
