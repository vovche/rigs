# Work Packet: QEMU Guest Agent transport

## Owned targets
- src/guest_agent.vala
- tests/test_guest_agent.vala

## Contract
Namespace Rigs, `GuestAgent : Object` constructor `(HostCommand? commands=null)`.
`public virtual Json.Node command(VmModel vm,string name,Json.Object? args=null,uint timeout_ms=5000) throws Error`.
`public virtual void reboot(VmModel vm) throws Error` sends guest-shutdown mode reboot
without waiting for a response (QGA shutdown succeeds without a reply).
Parent adds model string guest_agent_socket default empty and persists it.
Libvirt: validate qemu:///session or qemu:///system and UUID, use HostCommand.run
virsh --connect URI qemu-agent-command UUID --timeout SECONDS SERIALIZED_JSON.
For reboot use --async instead of --timeout. No shell; parse envelope, raise on
error/malformed/missing return. Direct QGA: use vm.guest_agent_socket Unix socket,
NOT vm.qmp_socket. Fresh connection per command; bounded connect/I/O timeout.
Send 0xFF + guest-sync-delimited with random positive int64 token, discard stale
bytes until 0xFF reply and matching token; then send requested JSON command.
No QMP greeting/capabilities. Bound frames to 1MiB and sync scan to 2MiB.
Expected no-reply reboot should send and return, not report a fake timeout.
Never log guest payloads, credentials or stdout in warnings.
Supported commands for this module limited to guest-info/get-osinfo/get-devices,
guest-exec/exec-status, guest-file-open/write/read/close, guest-ping, guest-shutdown.
JSON type validation is mandatory (no GLib criticals for malformed peer data).
Use explicit IDs if protocol supports but sync + sequential single reply is
sufficient. Expose no arbitrary shell helper here; higher module owns fixed scripts.

## Tests
Rigs.Tests.TestGuestAgent methods test_libvirt, test_socket, test_errors.
Injected HostCommand fixture verifies exact structured JSON argv, OS strings,
protocol errors, bad URI/UUID rejected without execution. Local fake Unix peer
verifies sync sentinel/stale bytes and real response, no QMP handshake, errors,
no-reply reboot. No user VM/config/network access. Entire suite remains <1s.
Parent owns build registration and model fields; tell parent ready/errors.
