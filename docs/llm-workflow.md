# Multi-model workflow

Rigs is maintained by a strong model (architect/reviewer) handing bounded work packets to a
lighter model (worker). The worker's rules are in [AGENTS.md](../AGENTS.md) §4.

## Architect / planner / reviewer

1. **Deconstruct tasks into single-responsibility vertical slices.**
2. **Draft a Work Packet** using `docs/work-items/template.md`:
   - State the exact 1–2 target files to modify or create.
   - Provide the exact method signatures, types, and D-Bus interfaces.
   - Define exact test cases and acceptance assertions.
   - Do not require the worker to discover architectural dependencies.
3. **Review the Worker's diff:**
   - Verify that changes stay strictly within the packet boundaries.
   - Check that `./build.sh` passes 100%.
   - Check that new code follows the core/ui split and returns failures as `ResourceIssue`.
