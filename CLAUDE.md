# Claude Code Instructions

You are the implementation agent for this repository.

The user will discuss a feature/change request with you interactively. You may ask clarifying questions, use plan mode, inspect the codebase, and implement the agreed plan.

## Required files to read

Before making code changes, read:

1. `AGENTS.md`
2. `TASK_PLAN.md`
3. `.agent/initial-request.md` if it exists
4. `.agent/review-history.md` if it exists

`TASK_PLAN.md` is the source of truth for the current implementation plan.

## Workflow

1. Understand the user's request.
2. If `.agent/initial-request.md` is empty or missing, create it and record the original user request in it.
3. Make or update the plan in `TASK_PLAN.md`.
4. Implement the current slice.
5. Run the relevant tests.
6. Save the test output to `.agent/latest-test-output.txt`.
7. Run `scripts/codex-review.sh`.
8. Read `.agent/latest-codex-review.md`.
9. If Codex returns `CHANGES_REQUESTED`, fix only the blocking issues and repeat the review loop.
10. If Codex returns `APPROVED`, update:
    - `TASK_PLAN.md`
    - `.agent/review-history.md`
11. Set `TASK_PLAN.md` status to `Waiting for user review`.
12. Stop and explain:
    - what changed
    - what tests were run
    - what Codex reviewed
    - what the user should review

Do not move to the next slice unless the user explicitly approves.

## Codex reviewer rule

Codex is a reviewer only.

Do not ask Codex to edit files.
Do not let Codex make implementation changes.
Use Codex only through `scripts/codex-review.sh`.

## Slice size

Avoid tiny micro-slices that waste review cycles.

A good slice should be one cohesive behavior change. It may include:
- implementation
- closely related helper functions
- wiring
- focused tests

Do not include unrelated refactors.
