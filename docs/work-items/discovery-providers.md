# Work Packet: Resource discovery

## Targets (owned exclusively by worker)
- src/resource_discovery.vala
- tests/test_discovery.vala

## Contract
Use Rigs.HostCommand injected via constructor ResourceDiscovery(HostCommand? commands=null).
HostCommand.run(string[] argv,string? directory=null,uint timeout_ms=3000) throws Error
returns CommandResult fields output,error_output,exit_status. mode property.
VmModel parent adds `runtime` default podman, `resource_id` default empty,
`connection_uri` default qemu:///session; existing fields remain.
`DiscoverySource : Object` fields name, available(bool), message; constructor optional.
`DiscoveryResult : Object` public GenericArray<VmModel> candidates and
GenericArray<DiscoverySource> sources initialized empty.
`ResourceDiscovery.scan(GenericArray<VmModel> existing)` returns DiscoveryResult.
No writes and no lifecycle commands. Four independent probes:
- podman and docker: argv engine ps --all --no-trunc --format
  '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.State}}' (actual tab separators).
- virsh --connect qemu:///session list --all --uuid --name
- same qemu:///system
Each source success empty is available, failures have useful message distinct
from no resources. Catch errors per source. Avoid exposing full stderr or
credentials; classify tool-not-found, permission/connection and malformed output.
Containers: verify hexadecimal full ID (12..64), nonempty name, skip infra? no
need. vm_type=container, runtime=engine, resource_id=fullID, container_name=name,
id=engine+":"+fullID, name from runtime, subtitle engine + image, details=state,
icon network-server-symbolic. Never create shell commands from names.
Libvirt output is each `UUID name` (confirmed virsh upstream source), validate
UUID, vm_type=libvirt, resource_id=UUID, connection_uri=uri, id=uri+":"+UUID,
name=remaining string (allow spaces), subtitle=libvirt + uri, icon computer-symbolic.
Deduplicate discovered container full IDs across docker/podman aliases and
against existing type container runtime IDs; suppress legacy compose entries
when container_name matches (existing defaults runtime podman). Existing libvirt
by URI+UUID. No recursive filesystem or arbitrary process scans.
At most 4 command invocations per scan, no per-resource subprocess loops.

## Tests
Rigs.Tests.TestDiscovery methods test_containers, test_libvirt, test_failures,
test_duplicates. Fake HostCommand overrides run; record calls. Fixtures test
names/spaces/metacharacters treated as data, stopped containers, invalid IDs,
empty successful source, independent denied source, UUID+names, alias duplicate
IDs, legacy compose dedup, stable identities. No host runtime calls.
Parent owns build registration and UI. Tell parent when ready to compile.
