# Work Packet: [WP-ID] - [Short Title]

## 1. Goal & Context
[1-2 sentences explaining what need to be accomplished]

## 2. Target Files (Strict Boundary)
- **Primary:** `src/...`
- **Tests:** `tests/...`
- *No other files may be modified unless explicitly noted.*

## 3. Interface & Contract Specifications
```vala
// Exact types, signatures, and contracts required:
```

## 4. Platform & Invariant Reminders
- Spawning external commands MUST use `/bin/bash -c <cmd>` with `working_directory = vm.dir`.
- Tests must be headless and complete in under 1 second.

## 5. Acceptance Criteria
- [ ] `./build.sh` exits with 0 (clean compilation + all tests pass).
- [ ] [Specific unit test assertion 1]
- [ ] [Specific unit test assertion 2]

## 6. Verification Command
```bash
./build.sh
```
