# Guardrails: defect classes, rules and safe patterns

Each class below caused a real bug in Rigs. `scripts/lint.sh` enforces the rule IDs
mechanically; `scripts/lint_selftest.sh` proves every rule still fires. Both run in `./build.sh`.

To justify one exceptional line, end it with `// lint-allow: <RULE-ID> <reason>`.
Adding a rule: add the check to `lint.sh`, an injected violation to `lint_selftest.sh`, and a row here.

## Rules

| ID | Wrong | Right |
|----|-------|-------|
| CORE-01 | `Gtk.`/`Adw.`/`Gdk.` in `src/core` (core is linked into the headless tests without GTK) | keep logic in core, widgets in `src/ui`; pass data (e.g. `SystemDiagnostics.get_report(toolkit_versions)`) |
| CORE-02 | adding `gtk_dep`/`adw_dep` to `core_deps` to "fix" CORE-01 | move the code to `src/ui` instead |
| SILENT-01 | `warning("Start failed: %s", e.message)` in a driver (goes to the journal; the user sees nothing) | return a `ResourceIssue`: `ResourceIssue.from_error(e)`, `FailureRules.check_command(...)`, `FailureRules.diagnose(...)` |
| SILENT-02 | `new Thread<void*>(…)` in a driver (its result has nowhere to go) | driver methods block and return; `ResourceActions` owns the thread and publishes the issue |
| SILENT-03 | `ResourceStore.save(resources);` as a statement (a failed write loses the user's edits silently) | `Window.persist()`, which toasts `ResourceStore.save_error` |
| SPAWN-01 | `Process.spawn_*` (shell-parses the string, bypasses sandbox modes) | `new HostCommand().run({ argv… }, dir, timeout_ms)` |
| SPAWN-02 | `communicate_utf8` (throws on any non-UTF-8 byte, e.g. container logs) | `HostCommand.run`; for raw bytes `HostCommand.bytes_to_text(bytes)` |
| SPAWN-03 | shelling out to `socat` / `python3` for socket I/O | GIO `SocketClient` in-process: `HmpMonitor.send`, `GuestMedia` |
| SHELL-01 | `{ "/bin/bash", "-c", "echo '" + path + "'" }` (injection via `'` in a file name) | data as argv elements; `bash -c` only with `cmd`, `resource.start_cmd`, `resource.stop_cmd`, `resource.connect_cmd`; HMP arguments via `HmpMonitor.quote()` |
| APP-01 | `active_window as Window` (null while the shortcuts window is focused → duplicate main window) | `Application.main_window()` / `ensure_main_window()` |
| UI-01 | `toast.timeout = 0` (blocks every later toast in the overlay queue) | default timeout; keep persistent state on the card (warning icon) |
| MODEL-01 | `resource.issue_raised.connect(…)` in a widget (the model outlives the card: duplicate handlers after Undo, leaked widgets) | in `ResourceCard`: `track(resource.….connect(…))`; the window connects to the **card's** signal; `ResourceList.remove_card()` detaches |
| VALA-01 | `foreach (x in s.split(" ")[1:])` (slice of a temporary = use-after-free, segfault) | `string[] parts = s.split(" ");` then index or slice the local |
| VALA-05 | `x = p ?? value.split(",")[0]` (the temporary array is freed before the element is copied: garbage strings) | `string[] parts = value.split(","); x = p != null ? p : (parts.length > 0 ? parts[0] : "");` |
| VALA-02 | `string.split("\0")` (a Vala string ends at the first NUL) | read as `uint8[]` via `FileUtils.get_data` and split bytes |
| VALA-03 | `uint64 d = now - prev` (kernel counters such as iowait go backwards → wraps to 1.8e19) | `Metrics.saturating_delta`, `Metrics.delta_percent`, `Metrics.busy_percent` |
| VALA-04 | `public virtual` method with a body inside an interface (an inherited same-name method, e.g. `GApplication.hold`, is **not** bound; the no-op runs) | `public abstract` in interfaces; implement explicitly |
| VERSION-01 | `"0.9.0"` literal in code | `Config.VERSION` (from `project(version:)` in `meson.build`) |
| VERSION-02 | bumping `meson.build` but not `debian/changelog`, `packaging/rpm/rigs.spec`, `packaging/arch/rigs/PKGBUILD`, `snap/snapcraft.yaml`, metainfo `<release>` | bump all of them in one commit (see docs/packaging.md "Releasing") |
| BUILD-01..03 | new `src/*.vala` or `tests/test_*.vala` not in meson; `test_*` function not in `tests/main.vala` (it silently never runs) | register in all three places |
| I18N-01 | file uses `_()` but is missing from `po/POTFILES.in` | add the path |

## Semantics that lint cannot see (covered by tests)

- **CPU percentages are a share of the whole host** (all cores), the same scale as the host overview. Container runtimes report per core; convert with `Metrics.container_cpu_share`.
- **Telemetry polling must not change VM state on every tick.** Write settings (balloon polling period) only when stats are missing or stale (`GuestMemory.needs_polling`).
- **Process lookup** uses `ScriptedQemuDriver.find_vm_pid` (literal substring of `/proc/<pid>/cmdline`, skips self, zombies and kernel threads, largest RSS wins). Never `pgrep`.
- **Failure rules** (`src/core/failure_rules.vala`): each rule needs a test with the runtime's real wording (Podman, Docker, crun and QEMU word the same failure differently, e.g. a missing bind mount is `statfs …: no such file or directory` in rootless Podman).
- **Window state:** save `default_width`/`default_height` (the unmaximized size), debounced.

- **Every driver operation reports failure** (start, stop, connect, media, and a running VM exiting with an error). The `Driver` interface returns `ResourceIssue?`, so the compiler rejects a driver that does not answer. `ResourceActions` sets the `ResourceOperation`; the toast, card tooltip and dialog derive their headline from it (`ResourceIssue.headline`). There is no fire-and-forget `HostCommand.launch`: long-running user commands (viewers, foreground VMs) go through `FailureRules.check_command(..., timeout_ms = 0)` on the action's worker thread.
- **Enums, not strings:** `ResourceKind`, `ContainerRuntime`, `ExecutionMode`. A value that cannot be parsed from `vms.json` makes the file invalid (shown to the user) instead of reaching a command line.
- **No false alarms:** QEMU checks "process gone after start" only when `process_match` is set; an exit after a stop request is expected; a nonzero exit later than `STARTUP_WINDOW_US` is `RUN`, not `START`.
- **Known gap:** a compose resource without `container_name` cannot be checked after a successful `up -d` (service names and project labels differ between podman-compose and docker compose). Set `container_name` to get the check.
- **HMP errors:** `change`, `eject` and `system_powerdown` print nothing on success; `HmpMonitor.execute` throws QEMU's text otherwise.

## Vala test pitfalls

- `warning()` is fatal under `GLib.Test`: an expected failure path must not call `warning()`; return the error or use `debug()`.
- **Escape layers:** a shell snippet in a Vala string needs one Vala escape per backslash (`"printf '\\377'"` reaches bash as `printf '\377'`). Assert on the effect (e.g. `!text.validate()` before conversion) so a wrong escape fails the test instead of passing vacuously.
- Tests stay under 1 s in total and never touch real VMs: inject a `HostCommand` subclass (constructor `base.with_mode(ExecutionMode.NATIVE)`) overriding `run`/`run_capture_tail`, a `MockDriver` in a `new DriverRegistry()`, a fake `/proc` tree (`ScriptedQemuDriver.proc_root`), or a temporary Unix socket peer.
