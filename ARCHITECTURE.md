# Rigs Architecture & Design Specification

This document details the architectural principles, component interactions, and data flows of **Rigs**.

---

## 1. Architectural Overview

Rigs is a native GNOME app in **Vala**. Words used below (resource, driver, issue,
HostCommand, HMP/QMP) are defined in [CONTEXT.md](CONTEXT.md).

The code has two layers, enforced by the build:

| Layer | Directory | May use | Built as |
|-------|-----------|---------|----------|
| core | `src/core/` | GLib, GIO, JSON, libsoup, POSIX | static library `rigs-core` **without GTK** |
| ui | `src/ui/` | core + GTK 4 + Libadwaita | the `rigs` executable |

Tests link only `rigs-core`, so they cannot open windows (headless by construction).
Lint rules CORE-01/02 stop GTK from leaking into core.

```
 ui:   Window ── HostOverview            ResourceList ── ResourceCard ── IssueDialog
         │            ▲                        ▲               │
         │            │ HostStatus             │ ResourceStatus │ start/stop/connect/ISO
 core:   │      SystemMonitor (thread) ── Driver.check_status   ▼
         │                                         ResourceActions (thread per action)
         └── ResourceStore (vms.json)                    │ Driver.start() → ResourceIssue?
             WindowState (state.json)                    ▼
                                    DriverRegistry: ScriptedQemuDriver, ComposeDriver,
                                                    ContainerDriver, LibvirtDriver
                                                          │
                                   HostCommand (argv, LC_ALL=C, deadlines) / HmpMonitor
```

### Failure flow (never silent)

1. A card button calls `ResourceActions.start(resource)` (or stop/open_console/insert_iso/eject_iso).
2. `ResourceActions` runs the driver on a worker thread. Driver methods **block and return**
   `ResourceIssue?`: null on success, otherwise what went wrong.
3. `FailureRules` turns command output into an issue (regex rules for mounts, ports, KVM,
   name conflicts, rootless networking, OOM; otherwise the last output line).
4. `ResourceActions.publish` sets `resource.last_issue` and emits `resource.issue_raised`
   on the main loop. The card shows a warning icon, the window a toast with "Details",
   `IssueDialog` the explanation, a copyable command and the raw output.

---

## 2. Core Subsystems

### 2.1 Resources and drivers (`src/core/resource.vala`, `src/core/drivers/`)

- **`Resource`**: one managed thing. `kind` (`ResourceKind`) selects its driver; `runtime`
  (`ContainerRuntime`) is the container CLI. Both are enums: unknown values in `vms.json`
  are rejected at load time, never turned into commands.
- **`Driver`** (`driver.vala`): `start`, `stop`, `open_console`, `insert_iso`, `eject_iso`
  return `ResourceIssue?`; `check_status` returns `ResourceStatus`. All block.
- **`ScriptedQemuDriver`**: runs the user's script (`start_cmd`, default `./run-vm.sh`) via
  `HostCommand.run_capture_tail`, finds the QEMU process in `/proc` (`process_match`,
  `find_vm_pid`), controls it over the human monitor socket (`HmpMonitor`).
- **`ComposeDriver`**: `podman|docker compose up -d / down` or the user's commands; status from
  the container named `container_name`.
- **`ContainerDriver`**: one existing container by full ID (`podman|docker start/stop/inspect/stats`).
- **`LibvirtDriver`**: a local libvirt domain by URI + UUID (`virsh start/shutdown/dominfo/domstate`).
- **`DriverRegistry`**: `ResourceKind` → driver. `new DriverRegistry()` is empty for tests.

### 2.2 Telemetry (`src/core/monitor.vala`, `src/ui/sparkline.vala`)

- `SystemMonitor` polls on its own thread (1 s focused, 3 s in background, paused when
  minimized) and works on JSON copies of the resources, never the UI's objects.
- CPU is always a share of the whole host (`Metrics`).
- Optional guest RAM (`guest_memory.vala`): QMP balloon statistics or libvirt `dommemstat`,
  validated for range and freshness; polling settings are written only when stats are stale.
- `SmoothSparkline` draws the 25-sample history with Cairo Bezier curves.

### 2.3 Optical drive (ISO)

`ResourceCard` → `Window.choose_and_insert_iso` (Gtk.FileDialog) → `ResourceActions.insert_iso`
→ `ScriptedQemuDriver` sends `change cdrom "<quoted path>"` over HMP; QEMU's reply text, if any,
becomes a MEDIA issue. Other kinds return an "unsupported" issue.

### 2.4 Adding a resource

The header has one "+" button (Ctrl+N); the magnifier (Ctrl+F) only filters resources already
added. `AddResourceDialog` page 1 lists what `ResourceDiscovery` finds on this computer
(containers, libvirt domains; scanned automatically, read-only) and manual presets
("From a folder", "Compose project", "QEMU start script"). `ResourcePresets` reads the folder:
`compose.yaml` → container_name, Windows image, port summary; `run-vm.sh` → process match,
monitor/QMP/guest-agent sockets and a SPICE connect command (plain `VAR=value` expansion only).
Page 2, `ResourceEditorPage`, shows only the fields relevant to the kind, explains what an empty
field means, and enables "Add" only while `ResourcePresets.validate()` returns null.

### 2.5 Persistence

- **`~/.config/rigs/vms.json`** (`ResourceStore`): human-editable; keys keep their historical
  names (`"type"` = kind, `"process_name"` = process_match). A damaged file is preserved, shown
  in a dialog and never overwritten; a failed save is shown as a toast (`Window.persist`).
- **`~/.config/rigs/state.json`** (`WindowState`): window size and expanded cards; damaged = defaults.

---

## 3. Directory Layout

```
rigs/
├── CONTEXT.md                 # Glossary: read first
├── ARCHITECTURE.md            # This file
├── AGENTS.md                  # Rules for coding agents
├── build.sh                   # Build + test + install (the oracle)
├── run.sh                     # Run the built app with a throwaway config
├── scripts/lint.sh            # Mechanical guardrails (docs/guardrails.md)
├── src/
│   ├── core/                  # GLib-only library rigs-core
│   │   ├── resource.vala          # Resource, ResourceKind, ContainerRuntime, ResourceStatus
│   │   ├── resource_store.vala    # vms.json
│   │   ├── resource_presets.vala  # settings read from compose.yaml / run-vm.sh, validation
│   │   ├── resource_issue.vala    # ResourceIssue, ResourceOperation, FailureCategory
│   │   ├── failure_rules.vala     # output → ResourceIssue
│   │   ├── resource_actions.vala  # runs drivers off the main thread, publishes issues
│   │   ├── host_command.vala      # every host process (ExecutionMode)
│   │   ├── qemu_monitor.vala      # HMP client
│   │   ├── monitor.vala, metrics.vala, window_state.vala, search_provider.vala
│   │   ├── guest_*.vala, windows_guest_installer.vala, resource_discovery.vala
│   │   └── drivers/               # driver.vala, driver_registry.vala and one file per kind
│   └── ui/                    # GTK widgets
│       ├── main.vala, application.vala, window.vala
│       ├── host_overview.vala, resource_list.vala, resource_card.vala, sparkline.vala
│       ├── add_resource_dialog.vala   # the only "add" flow: discovered + manual presets
│       ├── resource_editor_page.vala  # settings form with live validation
│       └── *_dialog.vala          # guest tools, driver setup, issue
├── tests/                     # GLib.Test, headless, < 1 s; test_regressions.vala for bug repros
├── data/, po/, snap/
└── docs/                      # guardrails.md, packaging.md, llm-workflow.md, work-items/
```

## 4. Discovery and host access

`HostCommand` owns executable argv, working directories, locale and deadlines.
Native/classic deployment executes directly. Flatpak is not supported (the mode
`unsupported-sandbox` refuses every command with an explicit error). Strict Snap permits only the connected Docker
Snap executable; absent connections are explicit failures, never an empty host.
No command transport uses process-name/global kill for timeout cleanup.

`ResourceDiscovery.scan(existing)` returns candidates plus per-source connection
status. Four bounded inventory queries cover Podman, Docker, libvirt session and
system. Stable IDs and legacy container names suppress duplicates. It performs
no persistence/lifecycle changes. `DiscoveryDialog` runs it off the main thread;
registration is explicit. Existing configuration is not migrated or replaced.

`ContainerDriver` controls discovered containers by engine + full ID and
`LibvirtDriver` libvirt domains by local URI + UUID. They never invent shell
commands from labels or names, destroy domains, remove containers, or stop an
entire Compose project. Legacy scripts remain an explicit manual path.

Guest integration has diagnostic states independent from host RAM. QMP checks
that balloon0 exists; libvirt uses live dommemstat polling. Windows/Linux
counter semantics remain distinct. `GuestToolsDialog` configures the OS/channel
and provides official driver/setup guidance, without claiming driver absence
from missing statistics. Its Windows driver action opens `GuestDriverSetupDialog`.


## 5. Windows guest driver setup

`GuestAgent` owns a dedicated QGA socket transport (sync-delimited framing,
limits and deadlines) or libvirt `qemu-agent-command`. `GuestMedia` separately
uses QMP/libvirt to enumerate and attach media only to empty optical drives.
QMP insertion uses an owned read-only block node and atomic insert, avoiding
replacement of media inserted concurrently. Container mount inspection maps
host paths or stages a private verified copy in a writable storage bind mount.

`GuestToolsPackages` uses libsoup HTTPS with a fixed version/hash catalog,
private cache and temporary files, size/time limits and cancellation. Local
artifacts retain their computed SHA256. `WindowsGuestInstaller` checks enabled
QGA commands, OS and privileges, uploads through guest-file APIs, and runs a
fixed encoded PowerShell helper. SHA256 and a valid Red Hat Authenticode signer
are checked in the guest before executing the package with no forced restart.
Neither execution policy nor certificate verification is disabled.

Private durable journals and per-target markers prevent duplicate installs.
After a QGA service restart, recovery reads the existing Windows outcome rather
than launching another installer. Unknown outcomes remain pending; only verified
terminal outcomes release the marker. A reboot is a separate UI confirmation.
`GuestDriverSetupDialog` performs I/O on worker threads using a model snapshot;
installation/recovery cannot be dismissed while active, downloads can be canceled.
Without an agent, the ISO route requires an initial manual Windows console step.
WinRM is deliberately outside this product workflow.
