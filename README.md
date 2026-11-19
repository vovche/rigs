# Rigs ⚡

**Website and downloads: [vovche.github.io/rigs](https://vovche.github.io/rigs/)** ·
[Українською](https://vovche.github.io/rigs/uk/) · [Releases](https://github.com/vovche/rigs/releases)

**Rigs** is a native, lightweight GNOME application (built with **Vala**, **GTK 4**, and **Libadwaita**) for managing and monitoring local developer virtual environments, micro-VMs, and containerized operating systems.

Designed as an ultra-fast, zero-overhead hub for mixed workflows:
- **Standalone QEMU / KVM micro-VMs** (direct QEMU scripts, custom OVMF UEFI, SPICE & audio passthrough).
- **Podman / Docker Compose environments** (e.g. Windows in container via `dockur/windows`, Linux containers).

---

## Key Features

- **Instant Startup (~15–20 ms):** Transpiled to native C via Vala and compiled directly with GCC — zero interpreter overhead.
- **Ultra-low Memory Footprint (~15–20 MB):** Pure GObject native baseline.
- **100% GNOME HIG Compliant:**
  - `Adw.HeaderBar` with title and primary menu (Burger menu ☰).
  - `Adw.ToastOverlay` with in-app notifications and `Undo` support.
  - `Adw.Clamp` for clean, adaptive centering on ultrawide displays.
  - Smart contextual actions (one-click Start / Connect / Stop).
  - Safe confirmation via `Adw.AlertDialog` on removal.
  - Native directory picker (`Gtk.FileDialog`) with auto-detection of `compose.yaml` or `run-vm.sh`.
- **Live Host Telemetry & Smooth Sparklines:** Real-time host CPU% and RAM usage via direct `/proc` inspection and smooth canvas charts inspired by GNOME Resources.
- **Optical Drive (ISO) Support:** Hot-plug and eject live ISO images directly to/from QEMU monitor socket without VM restarts.
- **Internationalization (i18n):** Translation catalogs for 19 languages (Ukrainian, English GB & standard fallback, Polish, Czech, French, German, Spanish, Portuguese, Italian, Dutch, Chinese, Japanese, Indonesian, Turkish, Kazakh, Belarusian, Slovenian, Arabic & Hebrew with native RTL support).
- **State Persistence:** Remembers window size, maximized state, and expanded details between launches.

---

## First launch and resource discovery

A new installation starts without personal machine definitions. The discovery
window checks Podman, Docker, and both local libvirt connections
(`qemu:///session`, `qemu:///system`). Select **Add** for each resource you want
Rigs to manage. **Find Resources** in the header rescans later; manual script
registration remains available through the Add button.

Discovery lists running and stopped resources accessible to the current user
and current container-engine context. It never starts/stops resources, installs
a runtime, elevates privileges, or scans the filesystem recursively. Engine
aliases and already registered resources are deduplicated. Per-connection
messages distinguish an empty inventory from missing tooling, permissions,
connection errors and timeouts. Containers use runtime IDs; libvirt domains
use URI + UUID. Importing an individual Compose container controls only that
container, not its whole project.

Existing `vms.json` entries and custom commands are preserved. Empty files/lists
never recreate sample machines. Malformed configuration is preserved and blocks
registration until repaired. Unsupported driver types cannot invoke a fallback
driver. Standalone QEMU scripts stay a manual/native option: observing a process
does not reveal a reliable persistent start command or safe stop target.


## Installation & Packaging

Requires GNOME 46+ libraries (GTK 4.10+, Libadwaita 1.5+): Ubuntu 24.04+, Debian 13+,
Fedora 40+, Arch. Runtime tools (`podman` or `docker`, optional `qemu`, `virsh`,
`virt-viewer`, `remmina`) come from your distribution.

### Ubuntu / Debian (.deb)
Download `rigs_*.deb` from the [website](https://vovche.github.io/rigs/#install) or the [releases](https://github.com/vovche/rigs/releases), then:

```sh
sudo apt install ./rigs_*.deb
```

### Fedora (.rpm)

```sh
sudo dnf install ./rigs-*.rpm
```

### Arch Linux
Install the release package straight from GitHub: `sudo pacman -U <link from the website>`.
From a clone, one command builds a real pacman package and installs it:

```sh
git clone https://github.com/vovche/rigs && cd rigs
scripts/package.sh arch-install
```

Uninstall with `sudo pacman -R rigs`. The PKGBUILDs live in `packaging/arch/`.

### Build packages yourself
`scripts/package.sh deb|rpm|arch|all` builds packages from the committed tree in clean
podman containers (Ubuntu 24.04, Fedora 42, Arch), running all tests, into `dist/`.
Details and the release checklist: [docs/packaging.md](docs/packaging.md).

### From source (development)
`./build.sh` builds, tests and installs into `~/.local`.

### Flatpak: not supported
Rigs manages host processes, `/proc` and QEMU monitor sockets. A Flatpak sandbox
hides all three (its own PID namespace, private `/tmp`), so most VM features
would not work, and the full host access needed to work around that defeats the
sandbox. Use the native package or Snap. Started inside Flatpak, Rigs reports
every host command as unsupported instead of failing silently.

### Snap
`snap/snapcraft.yaml` provides strict Snap packaging with the GNOME extension.
Strict Snap supports Docker through the Docker Snap's client and socket:

```sh
sudo snap connect rigs:docker docker:docker-daemon
sudo snap connect rigs:docker-executables docker:docker-executables
```

These privileged connections may require a Snap Store declaration. Strict
confinement does not permit arbitrary host executables: Podman, libvirt and
custom host scripts require native/classic deployment or a future host broker.
A classic package, if provided, requires separate Store approval. No published
Snap/Flathub listing or completed package build is implied by these manifests.

See [Snap Docker interfaces](https://snapcraft.io/docs/reference/interfaces/docker-interface/).

---

## Building from Source

### Dependencies
- `valac` (>= 0.56)
- `meson` (>= 0.59)
- `ninja`
- `libadwaita-1` (>= 1.5)
- `gtk4` (>= 4.10)
- `json-glib-1.0`
- `libsoup-3.0`
- `gettext`

### Build commands
```bash
meson setup build
ninja -C build
./build/src/rigs
```

### Install locally
```bash
./build.sh
```

---

## License

Apache License 2.0.

### Guest memory statistics (QEMU and Compose)

Host/container consumption and guest RAM usage are displayed separately. To
collect guest RAM, run QEMU with a VirtIO balloon device named `balloon0` and a
local QMP Unix socket, for example:

```sh
-device virtio-balloon-pci,id=balloon0,guest-stats-polling-interval=5 \
-qmp unix:/storage/rigs-qmp.sock,server=on,wait=off
```

For a container VM, place the socket in an existing host-mounted directory.
Keep the socket local and accessible only to the VM owner. In the VM's entry
in `~/.config/rigs/vms.json`, configure its **host** path:

```json
"qmp_socket": "/path/to/vm/storage/rigs-qmp.sock",
"guest_os": "windows"
```

For Windows, install the VirtIO Balloon driver and run `BalloonService`
(`blnsvr`). For Linux, use the guest's virtio_balloon driver and set `guest_os`
to `linux`. Rigs enables a five-second statistics polling interval; it never
issues balloon resize commands. Device/launch changes require a VM restart.

Rigs validates guest counters and timestamps. Missing or stale statistics show
“Guest statistics unavailable”; host consumption is never substituted. For
Windows, used RAM is total minus `stat-free-memory`, which VirtIO-Win populates
from `GlobalMemoryStatusEx.ullAvailPhys`. For Linux it is total minus
`stat-available-memory`, preserving reclaimable cache semantics. Samples can
differ slightly from Task Manager due to polling time and rounding.

Protocol: [QEMU balloon statistics](https://www.qemu.org/docs/master/interop/virtio-balloon-stats.html).
Windows mapping: [VirtIO-Win memory statistics](https://github.com/virtio-win/kvm-guest-drivers-windows/blob/master/Balloon/app/memstat.cpp).

### Guest integration guidance

For QEMU/libvirt VMs, use the setup button beside guest memory to choose the
OS and configure statistics. Rigs distinguishes an unconfigured channel,
connection failure, missing `balloon0` device, guest not reporting, stale
samples, and unsupported counters. The setup dialog links official VirtIO-Win
downloads and explains the Balloon driver/service. These observations do not
prove that drivers are missing. **Set Up Windows Drivers…** opens the driver
setup workflow described below. Known dockur/dockurr Windows VM images expose this setup
action when discovered; generic containers are not treated as Windows VMs.

Libvirt VMs use `virsh dommemstat` with five-second live polling, without a
separate QMP socket or memory resizing. Select the guest OS before collecting
these statistics. Native/Flatpak/Snap routing is covered by headless tests;
Flatpak and Snap installation/build tests remain separate release checks.

Configuration follows `XDG_CONFIG_HOME` (normally `~/.config/rigs`). Flatpak and
Snap use their own application configuration directories; they do not silently
import the native configuration or its custom commands.

### Windows driver setup

Rigs uses QEMU Guest Agent (QGA) for automatic Windows driver installation.
WinRM is not part of this workflow. A working agent with administrator rights
is required; Rigs checks the guest OS, x86/x64 architecture and required QGA
commands before enabling installation. Supported versions are Windows 10/11
and Server 2016/2019/2022/2025.

For libvirt, configure a virtio channel named `org.qemu.guest_agent.0` in your
VM manager. For standalone QEMU, create a **separate** QGA Unix socket, for
example (omit controllers already present):

```sh
-chardev socket,path=/storage/rigs-qga.sock,server=on,wait=off,id=rigs-qga \
-device virtio-serial-pci \
-device virtserialport,chardev=rigs-qga,name=org.qemu.guest_agent.0
```

Configure its host path through guest integration or `guest_agent_socket` in
`vms.json`. This is distinct from `qmp_socket`, which provides balloon telemetry
and CD control. Keep both sockets accessible only to the VM owner. A new
virtual device/channel may require a VM restart.

The setup dialog downloads a pinned official VirtIO-Win package over HTTPS,
verifies SHA256, uploads it through QGA, and requires Windows to validate its
Red Hat Authenticode signature before execution. A local EXE is also supported;
its digest is checked again inside Windows and the same signer validation
applies. Installing requires an explicit confirmation naming the VM. The
installer runs with `/quiet /norestart`; a requested restart is a separate
confirmed action. An untrusted or unverifiable signature blocks installation.
Tiny/custom Windows images must retain PowerShell and certificate validation.

If QGA is missing, use **Download and Attach VirtIO ISO** or choose a local ISO.
Rigs enumerates optical drives and accepts only an empty one. Open the Windows
console and run `virtio-win-guest-tools.exe` as administrator, retaining the
Balloon driver and QEMU Guest Agent. This initial bootstrap needs one manual
step. Rigs cannot execute software in an unprepared guest. A local ISO is
format-checked; use a trusted source. Downloaded ISO images also have a pinned
SHA256. No CD drive is created automatically.

Jobs retain private host journals under `$XDG_STATE_HOME/rigs/guest-tools`
(normally `~/.local/state/rigs/guest-tools`) and Windows logs under
`C:\ProgramData\Rigs\GuestTools\<job>`. If an agent restart interrupts the
connection, **Check Installation Result** recovers the existing outcome.
Unknown jobs block another installation until a result is verified. Rigs does
not kill Windows installers on timeout. Package cache uses
`$XDG_CACHE_HOME/rigs/guest-tools`.

Flatpak still requires access to the socket and media paths. Container media
uses an existing bind mount, or is staged in a writable `/storage` bind mount.
Libvirt requires host-readable media paths; portal-only paths may be unsuitable.
Strict Snap cannot access arbitrary host Unix sockets or libvirt: use a native
installation for these flows. Packaging manifests are not a claim of completed
Flatpak/Snap integration testing.

The package catalog and verification provenance are recorded in
[the VirtIO package catalog](docs/virtio-package-catalog.md). Headless tests use
fake agents/transports; they do not install software in a live Windows VM.
