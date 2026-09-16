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
- **Live Host Telemetry:** Real-time host CPU% and RAM usage via direct `/proc` inspection.
- **State Persistence:** Remembers window size, maximized state, and expanded details between launches.

---

## Building from Source

### Dependencies
- `valac` (>= 0.56)
- `meson` (>= 0.59)
- `ninja`
- `libadwaita-1` (>= 1.4)
- `gtk4` (>= 4.10)
- `json-glib-1.0`

### Build commands
```bash
meson setup build
ninja -C build
./build/src/rigs
```

### Install system-wide
```bash
meson install -C build
```

---

## License

Apache License 2.0.
