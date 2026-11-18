# Rigs glossary

One page of vocabulary. Code, docs and commit messages use these words with these meanings.

| Term | Meaning | Where |
|------|---------|-------|
| **Resource** | One thing Rigs manages: a VM started by a script, a compose project, a single container or a libvirt domain. Historical name in files and UI text: "VM". | `src/core/resource.vala` |
| **ResourceKind** | What a resource is: `QEMU`, `COMPOSE`, `CONTAINER`, `LIBVIRT`. Stored in `vms.json` as `"type"`. Selects the driver. | `resource.vala` |
| **ContainerRuntime** | `PODMAN` or `DOCKER`; `command()` is the CLI name. Stored as `"runtime"`. | `resource.vala` |
| **ResourceStatus** | One monitor sample: running, CPU % of the whole host, memory, guest memory. | `resource.vala` |
| **ResourceStore** | Reads/writes `~/.config/rigs/vms.json`. Never overwrites a damaged file. | `resource_store.vala` |
| **Driver** | Knows how to start/stop/inspect one `ResourceKind`. Methods block and return a `ResourceIssue?`. | `src/core/drivers/` |
| **ResourceActions** | Runs a driver call on a worker thread and publishes the returned issue. The UI's only way to act on a resource. | `resource_actions.vala` |
| **ResourceIssue** | A failure the user must see: title, explanation, advice, optional copyable command, raw output line. | `resource_issue.vala` |
| **ResourceOperation** | What the user asked for when it failed: `START`, `STOP`, `CONNECT`, `MEDIA`, or `RUN` (a running VM exited with an error). Selects the headline. | `resource_issue.vala` |
| **FailureRules** | Turns command output into a `ResourceIssue` with deterministic regex rules. | `failure_rules.vala` |
| **HostCommand** | The only way to run a host program: argv (no shell parsing), `LC_ALL=C`, deadlines, non-UTF-8 safe. | `host_command.vala` |
| **ExecutionMode** | Where Rigs runs: `NATIVE`, `SNAP_CLASSIC`, `SNAP_DOCKER`, `SNAP_RESTRICTED`, `UNSUPPORTED_SANDBOX` (Flatpak). Decides what host access exists. | `host_command.vala` |
| **process_match** | Substring of a QEMU command line used to find the VM process in `/proc` (`"process_name"` in `vms.json`). | `scripted_qemu_driver.vala` |
| **HMP** | QEMU human monitor: text commands over a Unix socket (`monitor_socket`). Used for powerdown and ISO changes. | `qemu_monitor.vala` |
| **QMP** | QEMU machine protocol (JSON) over `qmp_socket`. Used for guest memory statistics and media. | `guest_memory.vala`, `guest_media.vala` |
| **Guest agent (QGA)** | Agent inside the guest OS (`guest_agent_socket` or libvirt). Used to install Windows drivers. | `guest_agent.vala` |
| **core / ui** | The two code layers. core is GLib-only and unit-tested; ui is GTK. | `src/meson.build` |
