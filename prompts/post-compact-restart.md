# Post-Compact Restart Prompt

Read the durable workflow files before doing anything:

1. `STARTUP_PROMPT.md`
2. `CLAUDE.md`
3. `AGENTS.md`
4. `TASK_PLAN.md`
5. `.agent/initial-request.md`
6. `.agent/review-history.md`
7. `.agent/latest-codex-review.md` if present
8. `.agent/latest-test-output.txt` if present

Continue from the current status in `TASK_PLAN.md`.

Do not redo completed slices.

Do not move to the next slice unless the user explicitly approves.

Use the existing workflow:

1. Understand the next recommended slice.
2. Ask clarifying questions if needed.
3. Implement only that slice.
4. Run the relevant tests.
5. Save test output to `.agent/latest-test-output.txt`.
6. Run `scripts/codex-review.sh`.
7. If Codex returns `CHANGES_REQUESTED`, fix only blocking issues and run review again.
8. When Codex returns `APPROVED`, update `TASK_PLAN.md` and `.agent/review-history.md`.
9. Set status to `Waiting for user review`.
10. Stop and summarize what the user should review.

Before implementation, briefly summarize:
- what has already been completed
- what remains
- what slice you are about to work on
