# Agent Workflow

![Agent workflow meme](assets/agent-workflow-meme.png)

Small local workflow for using one agent as the implementer and a separate Codex
process as the reviewer.

## Start

- Claude Code: read `CLAUDE.md` and follow it.
- Codex CLI: read `AGENTS.md` and follow it.

Both entry files delegate to `IMPLEMENTER.md`, which contains the shared
implementation loop.

## Install Into A Codebase

From a fresh pull of this workflow repo, open the codebase where you want to use
the workflow and run:

```bash
/path/to/workflow/scripts/install-agent-workflow.sh
```

The installer copies the workflow files into that codebase and adds them to the
target repo's `.git/info/exclude`.

## Codex As The Implementer

The reviewer is a nested `codex exec` process and needs network access, so
`scripts/codex-review.sh` cannot run inside the Codex implementer's sandbox.
`.codex/rules/agent-workflow.rules` fixes this with a Codex execpolicy allow
rule that lets exactly that one script run outside the sandbox without
prompting — everything else the implementer does stays sandboxed, and the
reviewer itself still runs with `--sandbox read-only` in a temp working
directory. The flow stays identical for both implementers; no model-side
branching.

Project rules load only once you trust the repo's `.codex/` layer in Codex.
Until then, approve the escalation prompt when the script runs. Keep the rule
project-scoped: copied into `~/.codex/rules/` it would authorize
`scripts/codex-review.sh` in every repository, including untrusted ones.

## Review Loop

1. Implement one cohesive slice.
2. Run the relevant tests.
3. Save test output to `.agent/latest-test-output.txt`.
4. Run `scripts/codex-review.sh`.
5. Fix only blocking Codex feedback.
6. Stop after Codex approves so the user can review.

## Files

- `CLAUDE.md`: Claude Code entry instructions.
- `AGENTS.md`: Codex CLI entry instructions.
- `IMPLEMENTER.md`: shared implementer workflow.
- `TASK_PLAN.md`: durable task plan and status.
- `prompts/codex-review.md`: reviewer-only prompt.
- `prompts/pre-compact.md`: handoff prompt before compaction.
- `scripts/codex-review.sh`: launches the separate read-only Codex reviewer.
- `scripts/agent-status.sh`: optional status snapshot for the user or implementer.
- `.codex/rules/agent-workflow.rules`: lets Codex-as-implementer run the review script outside its sandbox.
