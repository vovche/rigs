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

## Adding a New Driver

To support another kind of resource (e.g. Incus, Firecracker):

1. Add a value to `ResourceKind` in `src/core/resource.vala` (with its `to_id()` string).
2. Create `src/core/drivers/my_driver.vala` implementing `Rigs.Driver`. Every method blocks and
   returns `ResourceIssue?` (null = success); use `FailureRules.check_command`/`diagnose` and
   `ResourceIssue.from_error` instead of logging:
   ```vala
   namespace Rigs {
       public class MyDriver : Object, Driver {
           public ResourceKind kind { get { return ResourceKind.MY_KIND; } }
           public ResourceIssue? start(Resource resource) { /* ... */ return null; }
           public ResourceIssue? stop(Resource resource) { /* ... */ return null; }
           public ResourceIssue? open_console(Resource resource) { /* ... */ return null; }
           public ResourceIssue? insert_iso(Resource resource, string iso_path) {
               return ResourceIssue.unsupported(_("This resource has no optical drive."));
           }
           public ResourceIssue? eject_iso(Resource resource) { return insert_iso(resource, ""); }
           public ResourceStatus check_status(Resource resource) { /* ... */ return ResourceStatus(); }
       }
   }
   ```
3. Register it in `DriverRegistry.with_defaults()` (`src/core/drivers/driver_registry.vala`).
4. Add the file to `core_sources` in `src/meson.build` (and to `po/POTFILES.in` if it uses `_()`).
5. Test it with a `HostCommand` subclass that returns scripted `CommandResult`s (see
   `tests/test_runtime_drivers.vala`). `./build.sh` must pass, including lint.

---

## Coding Style & Conventions

- **Indentation:** 4 spaces (no tabs).
- **Naming Conventions:**
  - Classes & Interfaces: `PascalCase` (`Resource`, `DriverRegistry`). Vocabulary: [CONTEXT.md](CONTEXT.md).
  - Methods & Functions: `snake_case` or `lowerCamelCase` consistent with Vala GLib conventions.
  - Properties & Signals: `snake_case` (`kind`, `start_requested`).
- **UI Design:** Adhere strictly to [GNOME Human Interface Guidelines](https://developer.gnome.org/hig/). Use Libadwaita standard widgets (`Adw.HeaderBar`, `Adw.PreferencesGroup`, `Adw.ActionRow`, `Adw.ToastOverlay`) instead of custom styling wherever possible.
- **Safety:** Never block the GTK main loop. Resource operations go through `ResourceActions` (worker thread); other blocking I/O runs on a worker thread or asynchronous GLib task.
