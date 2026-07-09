# Pre-Compact Handoff Prompt

Before the conversation is compacted, update the durable workflow files so the
next implementer session can continue safely.

Do not implement anything new.

Update `TASK_PLAN.md` with:

1. Original goal / feature request
2. Current status
3. Completed slices/parts
4. Remaining slices/parts
5. Current or next recommended slice
6. Files changed so far
7. Tests run so far
8. Latest Codex review result
9. Any known risks, unresolved questions, or important decisions
10. Any commands that should be run next

Update `.agent/review-history.md` with all Codex reviews so far.

Update `.agent/initial-request.md` if it is missing, empty, or incomplete.

Then produce a compact handoff summary with this format:

## Compact Handoff Summary

### Goal
...

### Completed
...

### Current Status
...

### Remaining Work
...

### Next Slice
...

### Files Changed
...

### Tests Run
...

### Latest Codex Review
...

### Important Context
...
