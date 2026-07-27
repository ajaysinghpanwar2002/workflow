# Codex Repository Instructions

## Code review rules

When performing a code review:

* Review only the current uncommitted changes and the current implementation slice.
* Before reviewing, read:

  1. `.agent/current-slice.md`
  2. `.agent/latest-test-output.txt`, if present
  3. `.agent/previous-codex-review.md`, if present. It is the last completed review and may belong to an earlier slice, so treat it as unverified context: use it only to check whether findings it raised about these same changes were addressed. Never treat a previous clean review as evidence that the current changes are clean.
* Inspect any surrounding implementation, tests, callers, configuration, and documentation needed to evaluate the changes correctly.
* Report actionable correctness, security, reliability, performance, maintainability, and test-coverage findings introduced by the current changes.
* Report where the changes do not match the goal in `.agent/current-slice.md`, or where they reach outside its stated scope.
* Do not report unrelated pre-existing problems.
* If there are no actionable findings, say so plainly. Do not imply concerns you are not reporting.
* Do not edit files or run commands that modify the repository.
* Do not run `scripts/codex-review.sh`.
* Do not start another reviewer.
* Report findings only.

## Interactive implementation

Implementation workflow instructions are intentionally not stored in this file.

An interactive implementation agent must follow `IMPLEMENTER.md` and
`TASK_PLAN.md` only when explicitly instructed to do so by the user.

