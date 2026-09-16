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

- **Process Spawning & Shell Invariant:**
  In GLib/Vala, `Process.spawn_command_line_async` and `Process.spawn_command_line_sync` **DO NOT invoke a shell**. They use `g_shell_parse_argv` and call `execvp` directly.
  - **Rule:** Never pass shell constructs (`cd`, `&&`, `|`, `>`, `&`, `nohup`) directly to `Process.spawn_command_line_*`.
  - **Rule:** Always use `Process.spawn_async` / `Process.spawn_sync` with `/bin/bash -c <cmd>` and explicitly pass `working_directory = vm.dir`.

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
3. Run `./build.sh` to compile and execute unit tests.
4. If a compiler error occurs, fix the specific type/line identified by `valac`.
5. Keep the diff minimal, atomic, and focused.

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
