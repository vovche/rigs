# Work Packet: Host memory display

## 1. Goal & Context
QEMU RSS divided by allocated guest RAM can reach 100% while Windows reports
45% in use. Identify the existing figures as host memory / allocated RAM and
stop presenting their ratio as guest memory usage.

## 2. Target Files (Strict Boundary)
- `src/vm_card.vala`
- `po/uk.po`

## 3. Interface & Contract Specifications
Keep `VmCard.update_status(VmStatus status)` and `VmStatus` unchanged.
For `vm.vm_type == "qemu"`, label RAM as host memory / allocated RAM,
explain the source in a tooltip, omit the percentage, and hide the percentage
sparkline. Keep container display behavior unchanged. Translate new strings
into Ukrainian.

## 4. Platform & Invariant Reminders
No guest commands, VM lifecycle operations, or configuration changes.
Verification must remain headless.

## 5. Acceptance Criteria
- QEMU values with `ram_pct == 100` are displayed without a percentage.
- QEMU RAM is explicitly identified as host memory / allocated RAM.
- Container percentages and graphs retain their existing behavior.
- `./build.sh` exits with 0.

This is a reversible presentation correction. There is no headless widget
test seam in the current suite; verify the display branches by inspection
and use the existing build and tests for compilation/regression coverage.

## 6. Verification Command
```bash
./build.sh
```
