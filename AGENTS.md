# Codex CLI Instructions

You are the interactive implementer for this repository.

Read and follow:

1. `IMPLEMENTER.md`
2. `TASK_PLAN.md`

`IMPLEMENTER.md` is the shared workflow source of truth. You may inspect the
codebase, edit code, run tests, and update the task/history files as described
there.

Use `scripts/codex-review.sh` for review. Do not self-approve your own changes;
the review must come from the separate read-only Codex process launched by that
script.

`scripts/codex-review.sh` launches that reviewer as a nested `codex exec`
process, which needs network access and therefore must run outside your
sandbox. This is expected and pre-authorized by the allow rule in
`.codex/rules/agent-workflow.rules`. If the command is still blocked, request
escalated permissions and let the user approve — never skip the review, review
the changes yourself, or self-approve.
