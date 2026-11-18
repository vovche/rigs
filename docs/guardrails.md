# Guardrails: defect classes, rules and safe patterns

Each class below caused a real bug in Rigs. `scripts/lint.sh` enforces the rule IDs
mechanically; `scripts/lint_selftest.sh` proves every rule still fires. Both run in `./build.sh`.

To justify one exceptional line, end it with `// lint-allow: <RULE-ID> <reason>`.
Adding a rule: add the check to `lint.sh`, an injected violation to `lint_selftest.sh`, and a row here.

## Rules

| ID | Wrong | Right |
|----|-------|-------|
| SILENT-01 | `warning("Start failed: %s", e.message)` in a driver (goes to the journal; the user sees nothing) | return a `StartupIssue`: `StartupDiagnostics.from_error(e, op)`, `check_command(...)`, `diagnose(...)` |
| SILENT-02 | `new Thread<void*>(…)` in a driver (its result has nowhere to go) | `StartupDiagnostics.run_in_background(vm, "name", () => job_returning_issue_or_null())` |
| SILENT-03 | `ConfigManager.save_vms(vms);` as a statement (a failed write loses the user's edits silently) | `Window.persist()`, which toasts `ConfigManager.save_error` |
| SPAWN-01 | `Process.spawn_*` (shell-parses the string, bypasses sandbox modes) | `new HostCommand().run({ argv… }, dir, timeout_ms)` |
| SPAWN-02 | `communicate_utf8` (throws on any non-UTF-8 byte, e.g. container logs) | `HostCommand.run`; for raw bytes `HostCommand.bytes_to_text(bytes)` |
| SPAWN-03 | shelling out to `socat` / `python3` for socket I/O | GIO `SocketClient` in-process: `HmpMonitor.send`, `GuestMedia` |
| SHELL-01 | `{ "/bin/bash", "-c", "echo '" + path + "'" }` (injection via `'` in a file name) | data as argv elements; `bash -c` only with `cmd`, `vm.start_cmd`, `vm.stop_cmd`, `vm.connect_cmd`; HMP arguments via `HmpMonitor.quote()` |
| APP-01 | `active_window as Window` (null while the shortcuts window is focused → duplicate main window) | `Application.main_window()` / `ensure_main_window()` |
| UI-01 | `toast.timeout = 0` (blocks every later toast in the overlay queue) | default timeout; keep persistent state on the card (warning icon) |
| MODEL-01 | `vm.startup_failed.connect(…)` in a widget (the model outlives the card: duplicate handlers after Undo, leaked widgets) | in `VmCard`: `track(vm.….connect(…))`; the window connects to the **card's** signal; call `card.detach()` before dropping a card |
| VALA-01 | `foreach (x in s.split(" ")[1:])` (slice of a temporary = use-after-free, segfault) | `string[] parts = s.split(" ");` then index or slice the local |
| VALA-02 | `string.split("\0")` (a Vala string ends at the first NUL) | read as `uint8[]` via `FileUtils.get_data` and split bytes |
| VALA-03 | `uint64 d = now - prev` (kernel counters such as iowait go backwards → wraps to 1.8e19) | `Metrics.saturating_delta`, `Metrics.delta_percent`, `Metrics.busy_percent` |
| VALA-04 | `public virtual` method with a body inside an interface (an inherited same-name method, e.g. `GApplication.hold`, is **not** bound; the no-op runs) | `public abstract` in interfaces; implement explicitly |
| VERSION-01 | `"0.9.0"` literal in code | `Config.VERSION` (from `project(version:)` in `meson.build`) |
| BUILD-01..03 | new `src/*.vala` or `tests/test_*.vala` not in meson; `test_*` function not in `tests/main.vala` (it silently never runs) | register in all three places |
| I18N-01 | file uses `_()` but is missing from `po/POTFILES.in` | add the path |

## Semantics that lint cannot see (covered by tests)

- **CPU percentages are a share of the whole host** (all cores), the same scale as the host overview. Container runtimes report per core; convert with `Metrics.container_cpu_share`.
- **Telemetry polling must not change VM state on every tick.** Write settings (balloon polling period) only when stats are missing or stale (`GuestMemory.needs_polling`).
- **Process lookup** uses `QemuDriver.find_vm_pid` (literal substring of `/proc/<pid>/cmdline`, skips self, zombies and kernel threads, largest RSS wins). Never `pgrep`.
- **Startup diagnostics** (`src/startup_diagnostics.vala`): each rule needs a test with the runtime's real wording (Podman, Docker, crun and QEMU word the same failure differently, e.g. a missing bind mount is `statfs …: no such file or directory` in rootless Podman).
- **Window state:** save `default_width`/`default_height` (the unmaximized size), debounced.

- **Every driver operation reports failure** (start, stop, connect, media, and a running VM exiting with an error). Pick the `ResourceOperation`; the toast, card tooltip and dialog derive their headline from it (`StartupDiagnostics.headline`). There is no fire-and-forget `HostCommand.launch`: long-running user commands (viewers, foreground VMs) go through `check_command(..., timeout_ms = 0)`, which waits on a worker thread.
- **No false alarms:** QEMU checks "process gone after start" only when `process_name` is set; an exit after a stop request is expected; a nonzero exit later than `STARTUP_WINDOW_US` is `RUN`, not `START`.
- **Known gap:** a compose resource without `container_name` cannot be checked after a successful `up -d` (service names and project labels differ between podman-compose and docker compose). Set `container_name` to get the check.
- **HMP errors:** `change`, `eject` and `system_powerdown` print nothing on success; `HmpMonitor.execute` throws QEMU's text otherwise.

## Vala test pitfalls

- `warning()` is fatal under `GLib.Test`: an expected failure path must not call `warning()`; return the error or use `debug()`.
- **Escape layers:** a shell snippet in a Vala string needs one Vala escape per backslash (`"printf '\\377'"` reaches bash as `printf '\377'`). Assert on the effect (e.g. `!text.validate()` before conversion) so a wrong escape fails the test instead of passing vacuously.
- Tests stay under 1 s in total and never touch real VMs: inject a `HostCommand` subclass overriding `run`, a fake `/proc` tree (`QemuDriver.proc_root`), or a temporary Unix socket peer.
