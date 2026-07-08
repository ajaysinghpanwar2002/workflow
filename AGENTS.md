# Agent Rules

## Roles

Claude Code is the implementer.
Codex is the read-only reviewer.
The user is the final approver.

## Claude responsibilities

Claude may:
- inspect the codebase
- create or update the plan
- edit code
- run tests
- call the Codex review script
- apply Codex feedback
- update task/history files

Claude must not:
- move to the next slice without user approval
- make unrelated refactors
- ignore blocking Codex feedback without explaining why

## Codex responsibilities

Codex must:
- review the current diff
- check correctness
- check scope control
- check edge cases
- check tests
- check idiomatic usage for this repo
- return approval or blocking feedback

Codex must not:
- edit files
- run destructive commands
- suggest unrelated rewrites
- expand the task scope

## Review loop

The loop is:

1. Claude implements.
2. Claude runs tests.
3. Claude calls Codex.
4. Codex reviews.
5. Claude fixes blocking feedback.
6. Repeat until Codex approves.
7. Claude stops for user review.
