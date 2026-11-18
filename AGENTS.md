# Agent Operating Rules & LLM Collaboration Guide

Rigs is an ultra-fast, native GNOME Virtual Machine and Container Hub written in **Vala + Libadwaita (GTK 4)**.

Architects and reviewers: see `docs/llm-workflow.md`. Workers: follow this file.

---

## 1. Progressive Read Order (Keep Context Small)

Do **NOT** load the entire codebase into context. Follow this order:

1. `CONTEXT.md` (one-page glossary), then `ARCHITECTURE.md` (layers, failure flow, layout).
2. The relevant contract or interface (e.g. `src/core/drivers/driver.vala`, `src/core/search_provider.vala`).
3. The assigned work packet (in `docs/work-items/`) or specific task description.
4. The target implementation file (under `src/`) and its corresponding unit test (under `tests/`).
5. Only inspect other files if an unresolved symbol requires it.

---

## 2. Hard Execution & Platform Invariants

- **The Oracle of Truth is `./build.sh`:**
  Build and test the project by running `./build.sh`.
  If the local host lacks `valac` or GTK4 development libraries, `./build.sh` automatically compiles and runs tests inside the rootless container `rigs-builder`.
  Never assume code is valid without a green `./build.sh` exit code.

- **Two layers:** `src/core` is GLib-only and is built without GTK (tests link only it); widgets go in `src/ui`. Lint CORE-01/02.

- **Process execution goes through `HostCommand` (`src/core/host_command.vala`):**
  It handles Snap host access, `LC_ALL=C`, deadlines and non-UTF-8 output.
  - Pass data (paths, names, IDs) as separate `argv` elements: `{ "podman", "logs", "--tail=30", name }`.
  - `/bin/bash -c` receives only a command the user configured verbatim (`resource.start_cmd`, `resource.stop_cmd`, `resource.connect_cmd`), with `directory = resource.dir`.
  - User start scripts run through `run_capture_tail` (never blocks on backgrounded children); short queries through `run` with a timeout.
  - Socket protocols (QMP, HMP, guest agent) use GIO sockets in-process; see `HmpMonitor`, `GuestMedia`.

- **Failures are never silent:** driver methods block and **return** `ResourceIssue?` (null = success); `ResourceActions` runs them off the main thread and publishes the issue (toast + card icon + `IssueDialog`). Drivers never call `warning()` or start threads (lint SILENT-01/02).

- **Guardrails are mechanical:** `./build.sh` runs `scripts/lint.sh` as the meson test `lint`.
  When lint reports a rule ID, or before you add a process call, a model signal connection, telemetry arithmetic, an interface or a new source/test file, read `docs/guardrails.md`.

- **Headless Unit Testing Invariant:**
  Tests in `tests/` must remain completely headless (no requirement for a running X11/Wayland display server or D-Bus daemon).
  - Use `MockDriver` or test-local models for tests.
  - Keep test execution time under 1 second.

- **Non-Destructive Operations:**
  Tests must never touch, alter, or terminate user VMs defined in `~/.config/rigs/vms.json` or live processes on the host.

---

## 3. Workflow for Small-Context Model (Worker)

1. Read **only** the provided work packet and the 1–2 target files.
2. Implement the requested contract without refactoring unrelated code.
3. Register every new file: `src/meson.build` (`core_sources` or `ui_sources`), `meson.build` `test_sources` (tests), `tests/main.vala` (`Test.add_func`), `po/POTFILES.in` (uses `_()`). Lint fails on any you miss.
4. Run `./build.sh`. Done means exit code 0: unit tests, `lint` and `lint-selftest` all OK.
5. If a compiler error occurs, fix the specific type/line identified by `valac`. If lint fails, apply the "right" pattern for that rule ID from `docs/guardrails.md`.
6. Fixing a bug: first add a failing reproduction to `tests/test_regressions.vala`, then fix until it passes.
7. Keep the diff minimal, atomic, and focused.

---

## 4. Commit Message Format (Ukrainian)

Every verified change must be committed following this Ukrainian structure:

```
<type>(<scope>): <короткий опис англійською або українською>

<Вимога> -> <Реалізація> (змінені файли, тести, логіка в деталях).

Чому: <Пояснення причини, вимоги задачі або архітектурного обґрунтування>.
```

Examples:
- `feat(shell): GNOME Shell Search Provider v2 для огляду та пошуку віртуальних машин`
- `fix(drivers): коректний запуск процесів у робочій директорії через bash shell`
- `test(mock): додано MockDriver для детермінованого юніт-тестування драйверів`
