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
