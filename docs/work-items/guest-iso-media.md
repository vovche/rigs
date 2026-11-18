# Work Packet: VirtIO ISO attachment

> **Historical packet.** Flatpak delivery was dropped on 2026-11-19; ignore its Flatpak parts (see README "Flatpak: not supported").

## Owned targets
- src/guest_media.vala
- tests/test_guest_media.vala

## Contract
`GuestOpticalDrive : Object` public strings id,current_iso (default empty), ctor
`GuestOpticalDrive(string id,string current_iso="")`.
`GuestMedia : Object` ctor `(HostCommand? commands=null)`.
`public virtual GenericArray<GuestOpticalDrive> list_drives(VmModel vm) throws Error`.
`public virtual void attach(VmModel vm,string iso_path,string drive_id) throws Error`.
For libvirt validate URI local session/system + UUID, list with
virsh --connect URI domblklist UUID --details; parse Type Device Target Source,
only cdrom, retain source paths incl spaces (split whitespace max4). Empty source
'-' => empty. Attach by re-listing selected target to ensure it exists and is
still empty, then virsh --connect URI change-media UUID target iso --insert --live.
Never --force/--config and never replace occupied media. Raise clear errors for
no CD drive, missing socket, permission, occupied target. Validate drive IDs.
For QEMU/compose/container use vm.qmp_socket Unix QMP. Implement private
bounded QMP JSON client (1s connect, per operation 3s overall, 1MiB frames),
qmp_capabilities then query-block. Require removable true AND a boolean tray_open
member (per QMP docs); removable alone also includes floppy drives. Prefer the
qdev identity (guest device ID or /machine/... QOM path), falling back to a valid
device identity when qdev is absent. No inserted member means empty; any inserted
member means occupied, including entries with no usable filename.
Attach revalidates the selected empty drive, including after container staging.
Create a uniquely named read-only raw node using blockdev-add with a file child;
keep its node-name below 32 characters. Open the selected tray with
blockdev-open-tray id,force=false, then blockdev-insert-medium id,node-name and
blockdev-close-tray id. Insert-medium rejects an occupied drive atomically; do not
use blockdev-change-medium, which can replace media inserted concurrently.
If opening or insertion fails, attempt blockdev-del only for the newly created
node. If closing fails after insertion, retain the attached medium and surface
the error; never detach it as cleanup. Do not issue remove-medium or force=true.
No guessed hard-coded drive names and no shell HMP string. The watchdog factory
must be static so its closure cannot retain/finalize the client on its own thread.
Container ISO paths must be translated through engine inspect --format '{{json .Mounts}}'
using stable resource_id for type container, container_name for legacy compose;
validate engine/name and parse Source/Destination. If source ISO is outside mounted
paths, choose writable /storage mount, stage under Source/.rigs-media/<sha256>.iso
with owner-only new directory and atomic copy (do not overwrite other files),
then use corresponding /storage/.rigs-media path. No binds/restarts/privilege
changes; fail actionable if no writable mount. Host-native/Flatpak staging uses
local file access; sandbox errors surfaced. Native QEMU uses absolute iso_path.
Require readable regular .iso file, basic ISO9660 CD001 descriptor at offset32769
(or expose validate_iso static helper tests); no massive fixture files.
May expose `public virtual Json.Node qmp(VmModel vm,string name,Json.Object? args=null)`
for fake injection so tests do not touch host sockets. Tests injected HostCommand
and fake qmp fixtures verify occupied media/disk exclusion, attachment arguments,
invalid engine/target rejected, libvirt path spaces, insertion-failure cleanup,
tray-close failure retaining inserted media, QOM identity selection, no force or
media-removal actions. The raw block-node cleanup is permitted only before a
successful insertion.
Parent owns artifact downloads/UI and build registration.
