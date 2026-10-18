# VirtIO-Win package catalog

Rigs pins release **0.1.302-1** rather than following a mutable latest alias.
Source directory:
https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.302-1/

| Artifact | Bytes | SHA256 |
| --- | ---: | --- |
| virtio-win-guest-tools.exe | 31642483 | `d8ae9ea1e943384ac195e012cd36f82c3161620e5fc9529be4e42e6f420e222d` |
| virtio-win-0.1.302.iso | 877373440 | `303f7ae40dad495d6ae474fdc571df58958a4dbc5c37a522d80f9a203867949d` |

These SHA256 digests were computed from complete files downloaded from the
fixed official HTTPS directory on 2026-10-18. They are Rigs catalog pins, not
upstream-published SHA256 attestations. The directory's CHECKSUM file covers
RPM files, not these two artifacts. Automated EXE installation additionally
requires Windows Authenticode validation and an exact allowed Red Hat signer
name. Custom Windows images with broken certificate trust fail closed.

Catalog updates require downloading the fixed release over HTTPS, reviewing
provenance, computing both complete-file digests, updating the code constants
and this record, and verifying the Windows signature. HTTP redirects are not
followed. Local EXEs use the same in-guest signature checks; local ISO provenance
is the user's responsibility.

Protocol references:
- https://www.qemu.org/docs/master/interop/qemu-ga-ref.html
- https://www.libvirt.org/manpages/virsh.html
- https://github.com/virtio-win/virtio-win-guest-tools-installer
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature

Automated tests cover fake QGA/libvirt/QMP exchanges, partial/tampered downloads,
package validation, guest execution scripts, outcomes and recovery. They never
modify a live user VM. Full installer execution and confined package end-to-end
validation remain separate integration checks.
