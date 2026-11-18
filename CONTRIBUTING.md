# Contributing to Rigs

Thank you for your interest in improving **Rigs**! We welcome bug reports, feature suggestions, documentation improvements, and code contributions.

---

## Code of Conduct

We strive to maintain a welcoming, respectful, and collaborative environment. Please treat all contributors with kindness and professional courtesy.

---

## Reporting Bugs & Issues

When reporting an issue or unexpected behavior:
1. Check if the issue has already been reported in [GitHub Issues](https://github.com/vovche/rigs/issues).
2. Because Rigs can be distributed as a **Snap** or compiled natively from source, always include system & environment diagnostics:
   - **In the GUI:** Open menu ☰ -> **About Rigs** -> **Troubleshooting / Copy Debug Information**.
   - **From Terminal:** Run `rigs --debug-info`.
3. Paste the generated Markdown diagnostics block into the issue description. This allows developers to instantly identify your packaging sandbox (Snap/Native), host OS, desktop session (Wayland/X11), and installed hypervisors (QEMU, KVM, Podman, Docker).

---

## Development Workflow

### 1. Prerequisites

To build and test Rigs locally, ensure you have the following installed:
- `valac` (>= 0.56)
- `meson` (>= 0.59)
- `ninja`
- `libadwaita-1-dev` (>= 1.4)
- `libgtk-4-dev` (>= 4.10)
- `libjson-glib-dev`

### 2. Building

```bash
# Setup build directory
meson setup build

# Compile
meson compile -C build

# Run executable
./build/src/rigs
```

### 3. Running Unit Tests

All data models, serialization logic, and driver abstractions are covered by automated `GLib.Test` suites:

```bash
meson test -C build --verbose
```

Before submitting a PR, make sure all tests pass without errors.

---

## Adding a New VM Driver

To add support for an additional hypervisor (e.g. `libvirt`, `VirtualBox`, `Incus`, `Firecracker`):

1. Create a new source file in `src/drivers/my_driver.vala`.
2. Implement the `Rigs.Driver` interface:
   ```vala
   namespace Rigs {
       public class MyDriver : Object, Driver {
           public string vm_type { get { return "my_driver"; } }
           public void start(VmModel vm) { /* ... */ }
           public void stop(VmModel vm) { /* ... */ }
           public void connect_vm(VmModel vm) { /* ... */ }
           public VmStatus check_status(VmModel vm) { /* ... */ }
           public void insert_iso(VmModel vm, string iso_path) { /* ... */ }
           public void eject_iso(VmModel vm) { /* ... */ }
       }
   }
   ```
3. Register the driver in `DriverRegistry` constructor (`src/drivers/driver_registry.vala`):
   ```vala
   register_driver(new MyDriver());
   ```
4. Add the new file to `src/meson.build` in `rigs_sources`.
5. Add unit tests verifying the driver in `tests/test_drivers.vala`.

---

## Coding Style & Conventions

- **Indentation:** 4 spaces (no tabs).
- **Naming Conventions:**
  - Classes & Interfaces: `PascalCase` (`VmModel`, `DriverRegistry`).
  - Methods & Functions: `snake_case` or `lowerCamelCase` consistent with Vala GLib conventions.
  - Properties & Signals: `snake_case` (`vm_type`, `start_requested`).
- **UI Design:** Adhere strictly to [GNOME Human Interface Guidelines](https://developer.gnome.org/hig/). Use Libadwaita standard widgets (`Adw.HeaderBar`, `Adw.PreferencesGroup`, `Adw.ActionRow`, `Adw.ToastOverlay`) instead of custom styling wherever possible.
- **Safety:** Always offload blocking I/O, heavy process execution, or network calls into background threads (`new Thread<void*>(...)`) or asynchronous GLib tasks so the GTK main loop stays responsive at 60+ FPS.
