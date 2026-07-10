# Implementer Workflow

You are the implementation agent for this repository.

## Required files

Before making code changes, read:

1. `TASK_PLAN.md`
2. `.agent/current-slice.md` if it exists
3. `.agent/initial-request.md` if it exists
4. `.agent/review-history.md` if it exists

`TASK_PLAN.md` is the source of truth for the overall implementation plan.
`.agent/current-slice.md` is the full spec of the slice being implemented — and
the only plan context the Codex reviewer receives, so keep it complete and
current-slice-only.

## Workflow

1. Understand the user's request.
2. If `.agent/initial-request.md` is empty or missing, create it and record the original user request in it.
3. Make or update the plan in `TASK_PLAN.md`, and write the full spec of the
   slice being implemented to `.agent/current-slice.md` (slice name, goal,
   in/out scope, plan steps, test command, implementation notes).
4. Implement one cohesive current slice.
5. Run the relevant tests.
6. Save the test output to `.agent/latest-test-output.txt`.
7. Run `scripts/codex-review.sh`.
8. Read `.agent/latest-codex-review.md`.
9. If Codex returns `CHANGES_REQUESTED`, fix only the blocking issues and repeat the review loop.
10. If Codex returns `APPROVED`, update `TASK_PLAN.md` and `.agent/review-history.md`.
11. Set `TASK_PLAN.md` status to `Waiting for user review`.
12. Stop and explain:
    - what changed
    - what tests were run
    - what Codex reviewed
    - what the user should review

Do not move to the next slice unless the user explicitly approves.
Do not include unrelated refactors.

## Current-slice hygiene

`.agent/current-slice.md` must describe only the slice under review. When the
user accepts a slice, move its details (deliverables, review outcome, commit
hash) into `.agent/review-history.md`, keep at most a one-line mention in
`TASK_PLAN.md`'s `Completed changes` section, and rewrite
`.agent/current-slice.md` for the next slice. Never let it accumulate past
slices.

## Review rule

Use `scripts/codex-review.sh` for review.

The review script starts a separate read-only Codex process. Do not ask that
reviewer process to edit files. Do not self-approve changes.
