# Implementer Workflow

You are the implementation agent for this repository.

This file describes the implementer role only. A Codex process started by
`scripts/codex-review.sh` (`codex exec review`) is the reviewer, not the
implementer, and must not follow this workflow — it follows the code review
rules in `AGENTS.md`.

## Required files

Before making code changes, read:

1. `TASK_PLAN.md`
2. `.agent/current-slice.md` if it exists
3. `.agent/initial-request.md` if it exists
4. `.agent/review-history.md` if it exists

`TASK_PLAN.md` is the source of truth for the overall implementation plan.
`.agent/current-slice.md` is the full spec of the slice being implemented. The
Codex reviewer reads it from the repository to learn what the slice was meant to
do, so keep it complete and current-slice-only.

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
8. Read `.agent/latest-codex-review.md` and apply the review decision policy below.
9. Repeat steps 4-8 while the review reports actionable findings.
10. When the review is clean, update `TASK_PLAN.md` and `.agent/review-history.md`.
11. Set `TASK_PLAN.md` status to `Waiting for user review`.
12. Stop and explain:
    - what changed
    - what tests were run
    - what Codex reviewed
    - what the user should review

Do not move to the next slice unless the user explicitly approves.
Do not include unrelated refactors.

## User acceptance

`.agent/current-slice.md` must describe only the slice under review. When the
user accepts a slice:

1. Move its details (deliverables, review outcome, commit hash) into
   `.agent/review-history.md`.
2. Keep at most a one-line mention in `TASK_PLAN.md`'s `Completed changes`
   section.
3. Rewrite `.agent/current-slice.md` for the next slice. Never let it accumulate
   past slices.
4. Once the outcome is archived, remove the spent review artifacts so no review
   from an accepted slice can be mistaken for the next slice's review:
   - `.agent/latest-codex-review.md`
   - `.agent/previous-codex-review.md`
   - `.agent/pending-codex-review.md`
   - `.agent/latest-codex-review-run.log`, if present

## Review rule

Use `scripts/codex-review.sh` for review. It launches a separate read-only
Codex reviewer in dedicated review mode (`codex exec review --uncommitted`),
which reviews the current staged, unstaged, and untracked changes and may read
the rest of the repository for context.

Do not ask that reviewer process to edit files. Do not substitute your own
review for it. Do not self-approve changes.

## Review decision policy

`.agent/latest-codex-review.md` contains human-readable review prose — not JSON
and not a status token. Read it and judge it on its content. The old
`REVIEW_STATUS: APPROVED` / `REVIEW_STATUS: CHANGES_REQUESTED` format is gone;
do not look for those lines or grep for approval words.

- **One or more concrete findings or review comments.** Address every actionable
  finding caused by the current slice, rerun the relevant tests, save the new
  output to `.agent/latest-test-output.txt`, and run
  `scripts/codex-review.sh` again.
- **A completed review that clearly reports no findings and no correctness
  concern.** Treat the review as clean: update `TASK_PLAN.md` and
  `.agent/review-history.md`, set the status to `Waiting for user review`,
  summarize, and stop.
- **Ambiguous, contradictory, truncated, empty, or failed review.** Do not infer
  approval. Set the status to `Blocked`, say what happened, and stop for the
  user. A nonzero exit from `scripts/codex-review.sh` means no review was
  produced: the script leaves `.agent/latest-codex-review.md` absent, and any
  earlier review sits in `.agent/previous-codex-review.md` — never read that as
  this round's result.
- **A finding that is unrelated, pre-existing, or would require expanding the
  agreed slice.** Do not silently broaden scope. Record it under
  `TASK_PLAN.md`'s `Open questions` and stop for user judgment when it cannot be
  resolved within the slice.
- **The same finding survives a reasonable attempted fix.** Do not loop
  indefinitely. Set the status to `Blocked` and explain the disagreement or the
  unresolved condition.

Passing tests are never on their own grounds for approval.
