# Rigs ⚡

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
- **Comprehensive Internationalization (i18n):** 19 fully translated languages (Ukrainian, English GB & standard fallback, Polish, Czech, French, German, Spanish, Portuguese, Italian, Dutch, Chinese, Japanese, Indonesian, Turkish, Kazakh, Belarusian, Slovenian, Arabic & Hebrew with native RTL support).
- **State Persistence:** Remembers window size, maximized state, and expanded details between launches.

---

## Installation & Packaging

### Snap Package
Rigs is packaged as a strict-confinement Snap using the official GNOME extension on `core24`:
```bash
snap install rigs
```
To build locally with Snapcraft:
```bash
snapcraft
```

### Flatpak
A Flatpak manifest (`io.github.vovche.Rigs.yaml`) targeting GNOME Runtime 46 is provided in the repository root.

---

## Building from Source

### Dependencies
- `valac` (>= 0.56)
- `meson` (>= 0.59)
- `ninja`
- `libadwaita-1` (>= 1.4)
- `gtk4` (>= 4.10)
- `json-glib-1.0`
- `gettext`
- `socat` (for QEMU monitor control)

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
