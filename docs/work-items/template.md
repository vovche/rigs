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
- Host programs run only through `HostCommand` with data as separate argv elements; `/bin/bash -c` only for the user's own `start_cmd`/`stop_cmd`/`connect_cmd`.
- New logic goes in `src/core` (no GTK); widgets in `src/ui`.
- Driver methods return `ResourceIssue?` instead of logging failures.
- Tests must be headless and complete in under 1 second.

## 5. Acceptance Criteria
- [ ] `./build.sh` exits with 0 (clean compilation + all tests pass, including `lint` and `lint-selftest`).
- [ ] Bug fix: a reproduction in `tests/test_regressions.vala` failed before the fix and passes after it.
- [ ] [Specific unit test assertion 1]
- [ ] [Specific unit test assertion 2]

## 6. Verification Command
```bash
./build.sh
```
