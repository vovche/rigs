# Work Packet: Discovered resource lifecycle

## Targets (owned exclusively by worker)
- src/drivers/managed_driver.vala
- tests/test_managed_driver.vala

## Contract
Implement `ManagedDriver : Object, Driver` constructor
`ManagedDriver(string kind, HostCommand? commands = null)` kind container/libvirt.
vm_type property returns kind. Parent registers instances for both kinds.
VmModel fields added by parent: runtime (default podman), resource_id (stable
full container ID or domain UUID), connection_uri (default qemu:///session).
HostCommand.run(argv, directory=null, timeout_ms=3000) throws Error returns
CommandResult output,error_output,exit_status; launch(argv,directory=null) throws Error.
Container allow engines podman/docker only; validate resource_id hex12..64.
Lifecycle argv `[runtime,start|stop,resource_id]`, use worker thread and run
bounded (stop timeout 35000 with CLI --time 30); no rm/down/kill. No shell.
Status authoritative inspect `--format {{.State.Running}}` stable ID, then stats
`--no-stream --format '{{.CPUPerc}}\t{{.MemUsage}}'` for Docker; Podman uses
`{{.CPU}}\t{{.MemUsage}}` confirm actual supported placeholders from docs.
CPU parse strip %, RAM retain used text before slash; do not guess guest RAM.
No fake zero on unreachable? VmStatus parent adds `bool status_available` default
false; set true on successful authoritative inspect, allow stopped result.
Libvirt validate UUID and URI limited qemu:///session or qemu:///system.
Lifecycle virsh --connect uri start|shutdown UUID; no destroy.
Status `virsh --connect uri dominfo UUID` LC_ALL=C; parse State (running,
paused,idle,in shutdown,pmsuspended active), Used memory as host/allocated
memory text (no percent), status_available true only valid output.
connect_vm for libvirt launch remote-viewer? Use `virt-viewer --connect URI UUID`;
container only explicit existing vm.connect_cmd via /bin/bash -c with vm.dir.
insert/eject no-op; UI hides unsupported optical controls for managed kinds.
Tests inject fake HostCommand. Lifecycle asynchronous tests avoid arbitrary
sleeps; optional test public static build argv helper if necessary; test status
and invalid resource rejection guaranteed. Rigs.Tests.TestManagedDriver methods
test_container_status, test_libvirt_status, test_invalid_targets. Parent build.
