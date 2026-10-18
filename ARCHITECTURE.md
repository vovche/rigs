# Rigs Architecture & Design Specification

This document details the architectural principles, component interactions, and data flows of **Rigs**.

---

## 1. Architectural Overview

Rigs is architected as a modular, responsive desktop control center following GNOME Human Interface Guidelines (HIG). It is written in **Vala**, compiling down to native C and GObject primitives without runtime language VM overhead.

```
┌─────────────────────────────────────────────────────────────┐
│                       Adw.Application                       │
│                              │                              │
│                      Rigs.Window (GTK4)                     │
│               ┌──────────────┴──────────────┐               │
│               │                             │               │
│         Host Overview               Virtual Machines        │
│      (CPU/RAM Sparklines)           (VmCard Expander)       │
└───────────────┬─────────────────────────────┬───────────────┘
                │                             │
    ┌───────────▼───────────┐     ┌───────────▼──────────────┐
    │     SystemMonitor     │     │      DriverRegistry      │
    │  (Worker Thread 1.5s) │     │  (Factory & Abstraction) │
    └───────────┬───────────┘     └───────────┬──────────────┘
                │                             │
        /proc/stat & /proc/meminfo    ┌───────┴───────┐
                                      │               │
                                 QemuDriver     ComposeDriver
                                      │               │
                                 socat/qemu       podman CLI
```

---

## 2. Core Subsystems

### 2.1 Driver Abstraction Layer (`src/drivers/`)
To support diverse hypervisor and container runtimes seamlessly without coupling GUI widgets to low-level shell commands, Rigs implements the **Driver Pattern**:

- **`Driver` Interface (`src/drivers/driver.vala`):**
  Defines the uniform lifecycle contract:
  - `start(VmModel vm)`: Launches the VM asynchronously in a background thread.
  - `stop(VmModel vm)`: Initiates graceful shutdown (ACPI powerdown or container stop).
  - `connect_vm(VmModel vm)`: Spawns the configured viewer client (SPICE, RDP, VNC).
  - `check_status(VmModel vm)`: Queries running state, CPU% and resident memory.
  - `insert_iso(VmModel vm, string iso_path)`: Mounts or hot-swaps an ISO disk image.
  - `eject_iso(VmModel vm)`: Unmounts or ejects media.

- **`DriverRegistry` (`src/drivers/driver_registry.vala`):**
  A singleton registry that registers available drivers and maps `vm_type` ("qemu", "compose") to their respective concrete implementations, with graceful fallback.

- **`QemuDriver` (`src/drivers/qemu_driver.vala`):**
  - Manages explicitly configured QEMU/KVM scripts. Host procfs monitoring requires native/classic deployment; sandboxed users should use libvirt.
  - Communicates with the QEMU Monitor socket via UNIX domain sockets (`socat`) to issue `system_powerdown`, `change cdrom <path>`, and `eject -f cdrom`.
  - Parses `/proc/[pid]/statm` for resident set size (RSS) memory consumption.

- **`ComposeDriver` (`src/drivers/compose_driver.vala`):**
  - Controls Podman and Docker Compose stacks (`podman compose up -d` / `down`).
  - Queries authoritative status and metrics through the configured Podman/Docker runtime using HostCommand. Unreachable and stopped are separate states.

### 2.2 Telemetry & Sparkline Engine (`src/sparkline.vala`, `src/monitor.vala`)
Inspired by the clean aesthetic of **GNOME Resources**:

- **Decoupled Monitoring Thread:** `SystemMonitor` executes in a dedicated OS thread every 1.5 seconds, avoiding any I/O or procfs stalls on the GTK main UI thread. Collected metrics are dispatched to the UI using `GLib.Idle.add()`.
- **Sliding History Ring Buffer:** Metrics are maintained in a 25-sample circular array.
- **Optional Guest RAM (`src/guest_memory.vala`):** The monitor queries a configured local QMP socket on its background thread. Balloon statistics from `balloon0` are validated for range and freshness (15 seconds). Windows uses total minus available physical RAM (`stat-free-memory` in VirtIO-Win); Linux requires `stat-available-memory`. Guest RAM and host process/container consumption have separate UI rows. Missing statistics remain unavailable. Polling never resizes guest RAM.
- **Smooth Bezier Spline Rendering:** The `SmoothSparkline` custom widget uses Cairo to draw continuous cubic Bezier curves through historical data points:
  - Fill: Linear vertical gradient from theme accent color (40% opacity) fading to transparent.
  - Stroke: Crisp anti-aliased contour line (2.0px width) with round line joins and caps.

### 2.3 Optical Drive (ISO) Hot-Swapping
Rigs allows developers and system administrators to hot-swap boot media and install images on live virtual machines without terminating the running instance:
1. `VmCard` exposes an Optical Drive ActionRow.
2. Selecting "Insert…" opens a native `Gtk.FileDialog` filtered to `*.iso` images.
3. The selected path is saved to configuration and immediately sent to the driver via socket command (`change cdrom /path/to/image.iso`).
4. "Eject" safely unmounts the disk image (`eject -f cdrom`).

### 2.4 State & Configuration Persistence (`src/vm_model.vala`)
- **VM Definitions (`~/.config/rigs/vms.json`):** Human-editable JSON format. Missing/empty configuration starts empty; malformed configuration is preserved and blocks registration. No personal VM entries are shipped. Optional `qmp_socket` (host Unix socket path) and `guest_os` (`windows` or `linux`) enable guest RAM telemetry.
- **Session State (`~/.config/rigs/state.json`):** Tracks window size, maximized state, and which VM cards were expanded by the user, preserving the layout between desktop restarts.

---

## 3. Directory Layout

```
rigs/
├── data/
│   ├── io.github.vovche.Rigs.desktop      # Desktop application launcher
│   ├── io.github.vovche.Rigs.metainfo.xml.in # AppStream metadata
│   ├── rigs.gresource.xml                # GResource bundle definition
│   └── style.css                         # Adwaita styling and color classes
├── src/
│   ├── drivers/                          # Pluggable VM & container drivers
│   │   ├── driver.vala                   # Driver interface contract
│   │   ├── driver_registry.vala          # Registry and factory
│   │   ├── qemu_driver.vala              # QEMU / KVM driver
│   │   └── compose_driver.vala           # Podman / Docker Compose driver
│   ├── add_dialog.vala                   # VM registration dialog
│   ├── application.vala                  # Adw.Application entrypoint & actions
│   ├── main.vala                         # Program main
│   ├── monitor.vala                      # Background procfs telemetry collector
│   ├── sparkline.vala                    # Cairo Bezier wave graph widget
│   ├── vm_card.vala                      # Expander row for VM management
│   ├── vm_model.vala                     # JSON model & config persistence
│   └── window.vala                       # Main window and UI composition
├── tests/
│   ├── main.vala                         # GLib.Test runner
│   ├── test_drivers.vala                 # Driver registry & driver unit tests
│   └── test_models.vala                  # Serialization & model unit tests
├── .github/
│   └── workflows/
│       └── ci.yml                        # GitHub Actions CI build & test
├── io.github.vovche.Rigs.yaml             # Flatpak packaging manifest
├── ARCHITECTURE.md                       # Architecture documentation
├── CONTRIBUTING.md                       # Contributor guide
├── meson.build                           # Root build configuration
└── README.md                             # Project overview and quick start
```

## 4. Discovery and host access

`HostCommand` owns executable argv, working directories, locale and deadlines.
Native/classic deployment executes directly. Flatpak wraps host commands with
`flatpak-spawn --host --watch-bus`. Strict Snap permits only the connected Docker
Snap executable; absent connections are explicit failures, never an empty host.
No command transport uses process-name/global kill for timeout cleanup.

`ResourceDiscovery.scan(existing)` returns candidates plus per-source connection
status. Four bounded inventory queries cover Podman, Docker, libvirt session and
system. Stable IDs and legacy container names suppress duplicates. It performs
no persistence/lifecycle changes. `DiscoveryDialog` runs it off the main thread;
registration is explicit. Existing configuration is not migrated or replaced.

`ManagedDriver` controls discovered containers by engine + full ID and libvirt
domains by local URI + UUID. It never invents shell commands from labels or
names, destroys domains, removes containers, or stops an entire Compose project.
Unknown driver kinds return null. Legacy scripts remain an explicit manual path.

Guest integration has diagnostic states independent from host RAM. QMP checks
that balloon0 exists; libvirt uses live dommemstat polling. Windows/Linux
counter semantics remain distinct. `GuestToolsDialog` configures the OS/channel
and provides official driver/setup guidance, without claiming driver absence
from missing statistics or automatically installing/restarting anything.
