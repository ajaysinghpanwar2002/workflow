---
name: workflow-state
description: Record progress and accepted slices without authorizing work.
---

# State

Update the plan in place. Preserve structure, decisions, accepted work, and
remaining order. Keep progress, blockers, and next action short; link details.
Never claim checks or reviews that did not happen.

Use `In progress` for authorized work, `Blocked` for required intervention,
and `Waiting for user review` after checks pass and all changed repositories
have current clean independent reviews.

After user acceptance and any authorized publication, append one short entry
to `.agent/review-history.md` and mark the slice accepted in `TASK_PLAN.md`.
Use `Done` only when all work is accepted; otherwise `Planned` unless the next
slice is explicitly authorized.

Only then delete each accepted repository's `.agent/latest-codex-review.md`,
`.agent/previous-codex-review.md`, `.agent/latest-test-output.txt`, and workspace
`.agent/reviews/<repository>/` directory. Keep `.agent/current-slice.md` until
the next authorized slice. Never reset unaccepted counters or erase failures
to obtain more attempts.
