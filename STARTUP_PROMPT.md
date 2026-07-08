Read `CLAUDE.md`, `AGENTS.md`, and `TASK_PLAN.md`.

You are the implementation agent. Codex is the read-only reviewer.

Work with me to understand the feature request. Use plan mode if helpful. Ask clarifying questions if needed. Then implement the agreed current slice.

When you have a diff ready:

1. Run the relevant tests.
2. Save test output to `.agent/latest-test-output.txt`.
3. Run `scripts/codex-review.sh`.
4. If Codex returns `CHANGES_REQUESTED`, fix only the blocking issues and run `scripts/codex-review.sh` again.
5. When Codex returns `APPROVED`, update `TASK_PLAN.md` and `.agent/review-history.md`.
6. Set `TASK_PLAN.md` status to `Waiting for user review`.
7. Stop and summarize:
   - what changed
   - what tests were run
   - what Codex reviewed
   - what I should review

Do not move to the next slice unless I explicitly approve.
