# Agent Workflow

![Agent workflow meme](assets/agent-workflow-meme.png)

Small local workflow for using one agent as the implementer and a separate Codex
process as the reviewer.

## Start

- Claude Code: read `CLAUDE.md` and follow it.
- Codex CLI:  read `AGENTS.md` You are the interactive implementer, not the Codex reviewer.

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

The reviewer is a nested `codex exec review` process and needs network access, so
`scripts/codex-review.sh` cannot run inside the Codex implementer's sandbox.
`.codex/rules/agent-workflow.rules` fixes this with a Codex execpolicy allow
rule that lets exactly that one script run outside the sandbox without
prompting — everything else the implementer does stays sandboxed, and the
reviewer itself still runs with `--sandbox read-only` in the repository. The
flow stays identical for both implementers; no model-side branching.

Project rules load only once you trust the repo's `.codex/` layer in Codex.
Until then, approve the escalation prompt when the script runs. Keep the rule
project-scoped: copied into `~/.codex/rules/` it would authorize
`scripts/codex-review.sh` in every repository, including untrusted ones.

## Review Loop

1. Implement one cohesive slice.
2. Run the relevant tests.
3. Save test output to `.agent/latest-test-output.txt`.
4. Run `scripts/codex-review.sh`. It launches Codex's dedicated review mode
   (`codex exec review --uncommitted`) read-only in this repository, so the
   reviewer selects the staged, unstaged, and untracked changes itself and can
   read the rest of the repo for context. Its prose lands in
   `.agent/latest-codex-review.md`.
5. Read that prose. Findings mean fix, retest, and review again.
6. A clearly clean review means stop so the user can review the slice.
7. A failed, empty, or ambiguous review means blocked — never self-approve. On
   failure the script writes no new `latest-codex-review.md`, so a stale review
   cannot pass as the current result.

The reviewer returns human-readable findings; there is no status token or JSON
verdict to parse. `IMPLEMENTER.md` holds the full decision policy.

## Files

- `CLAUDE.md`: Claude Code entry instructions.
- `AGENTS.md`: Codex CLI entry instructions, and the reviewer/implementer role
  boundary the dedicated reviewer reads.
- `IMPLEMENTER.md`: shared implementer workflow.
- `TASK_PLAN.md`: durable task plan and status.
- `prompts/pre-compact.md`: handoff prompt before compaction.
- `scripts/codex-review.sh`: launches the separate read-only Codex reviewer in
  dedicated review mode.
- `scripts/agent-status.sh`: optional status snapshot for the user or implementer.
- `.codex/rules/agent-workflow.rules`: lets Codex-as-implementer run the review script outside its sandbox.
