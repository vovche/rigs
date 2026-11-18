# Agent Operating Rules & LLM Collaboration Guide

Rigs is an ultra-fast, native GNOME Virtual Machine and Container Hub written in **Vala + Libadwaita (GTK 4)**.

This repository is optimized for multi-tier LLM workflows:
- **Architect / Planner / Reviewer:** Strong model (large context window) responsible for system design, interface contracts, bounded work packets, and final code reviews.
- **Worker / Implementer:** Fast/light model (small context window) responsible for executing single, bounded work packets with precision.

---

## 1. Progressive Read Order (Keep Context Small)

Do **NOT** load the entire codebase into context. Follow this order:

1. `ARCHITECTURE.md` (overview of subsystems and directory layout).
2. The relevant contract or interface (e.g. `src/drivers/driver.vala`, `src/search_provider.vala`).
3. The assigned work packet (in `docs/work-items/`) or specific task description.
4. The target implementation file (under `src/`) and its corresponding unit test (under `tests/`).
5. Only inspect other files if an unresolved symbol requires it.

---

## 2. Hard Execution & Platform Invariants

- **The Oracle of Truth is `./build.sh`:**
  Build and test the project by running `./build.sh`.
  If the local host lacks `valac` or GTK4 development libraries, `./build.sh` automatically compiles and runs tests inside the rootless container `rigs-builder`.
  Never assume code is valid without a green `./build.sh` exit code.

- **Process execution goes through `HostCommand` (`src/host_command.vala`):**
  It handles Flatpak/Snap host access, `LC_ALL=C`, deadlines and non-UTF-8 output.
  - Pass data (paths, names, IDs) as separate `argv` elements: `{ "podman", "logs", "--tail=30", name }`.
  - `/bin/bash -c` receives only a command the user configured verbatim (`vm.start_cmd`, `vm.stop_cmd`, `vm.connect_cmd`), with `directory = vm.dir`.
  - User start scripts run through `run_capture_tail` (never blocks on backgrounded children); short queries through `run` with a timeout.
  - Socket protocols (QMP, HMP, guest agent) use GIO sockets in-process; see `HmpMonitor`, `GuestMedia`.

- **Failures are never silent:** a driver operation that fails returns or publishes a `StartupIssue` (toast + card icon + details dialog). Drivers never call `warning()` and never start threads directly; see `StartupDiagnostics.run_in_background`.

- **Guardrails are mechanical:** `./build.sh` runs `scripts/lint.sh` as the meson test `lint`.
  When lint reports a rule ID, or before you add a process call, a model signal connection, telemetry arithmetic, an interface or a new source/test file, read `docs/guardrails.md`.

- **Headless Unit Testing Invariant:**
  Tests in `tests/` must remain completely headless (no requirement for a running X11/Wayland display server or D-Bus daemon).
  - Use `MockDriver` or test-local models for tests.
  - Keep test execution time under 1 second.

- **Non-Destructive Operations:**
  Tests must never touch, alter, or terminate user VMs defined in `~/.config/rigs/vms.json` or live processes on the host.

---

## 3. Workflow for Strong Model (Architect / Planner)

1. **Deconstruct tasks into single-responsibility vertical slices.**
2. **Draft a Work Packet** using `docs/work-items/template.md`:
   - State the exact 1–2 target files to modify or create.
   - Provide the exact method signatures, types, and D-Bus interfaces.
   - Define exact test cases and acceptance assertions.
   - Do not require the worker to discover architectural dependencies.
3. **Review the Worker's diff:**
   - Verify that changes stay strictly within the packet boundaries.
   - Check that `./build.sh` passes 100%.

---

## 4. Workflow for Small-Context Model (Worker)

1. Read **only** the provided work packet and the 1–2 target files.
2. Implement the requested contract without refactoring unrelated code.
3. Register every new file: `src/meson.build` (app), `meson.build` `test_sources` (tests), `tests/main.vala` (`Test.add_func`), `po/POTFILES.in` (uses `_()`). Lint fails on any you miss.
4. Run `./build.sh`. Done means exit code 0: unit tests, `lint` and `lint-selftest` all OK.
5. If a compiler error occurs, fix the specific type/line identified by `valac`. If lint fails, apply the "right" pattern for that rule ID from `docs/guardrails.md`.
6. Fixing a bug: first add a failing reproduction to `tests/test_regressions.vala`, then fix until it passes.
7. Keep the diff minimal, atomic, and focused.

---

## 5. Commit Message Format (Ukrainian)

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
