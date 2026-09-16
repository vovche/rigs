# Work Packets for LLM Agent Teams

This directory contains bounded work packets for coordinating between an **Architect model** (planning & reviews) and a **Worker model** (execution within a small context window).

## Lifecycle:
1. **Draft:** The Architect creates a task file from `template.md` (e.g. `001-add-wireguard-driver.md`).
2. **Execution:** The Worker reads ONLY that packet and the 1–2 target files, implements the changes, and runs `./build.sh`.
3. **Review & Merge:** The Architect reviews the resulting `git diff`, ensures all acceptance criteria pass, commits, and marks the packet as completed.
