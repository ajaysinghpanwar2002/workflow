# Agent Workflow

A local workflow where one agent implements and a separate read-only Codex agent reviews. One review per changed repository, two attempts maximum, no self-approval.

## Layout

One workspace directory per work item, normally a Jira ticket. It stays a plain directory. Each direct child is an independent Git repository.

```text
REC-2130/
├── AGENTS.md                  # implementer entry point
├── CLAUDE.md                  # @AGENTS.md
├── IMPLEMENTER.md             # the workflow
├── TASK_PLAN.md               # task state
├── scripts/codex-review.sh
├── .claude/skills/unslop/     # skill for Claude Code
├── .codex/skills/unslop/      # skill for Codex
├── .codex/rules/agent-workflow.rules
├── .agent/                    # initial-request.md, review-history.md
│   └── reviews/service-a/     # attempt counter, run log, pending review
├── service-a/
│   ├── AGENTS.md              # project owned, never touched
│   ├── CLAUDE.md              # project owned, never touched
│   └── .agent/                # AGENTS.md (reviewer), current-slice.md, reviews
└── service-b/
    └── ...
```

The workspace directory name is the branch name and the exact PR title. Branches come off `staging`, and PRs target `staging` only after tests pass, reviews are clean, and the user approves.

## Install

```bash
mkdir -p ~/Desktop/sprint-tasks/REC-2130
cd ~/Desktop/sprint-tasks/REC-2130

git clone <service-a-url> service-a
git clone <service-b-url> service-b

/path/to/workflow/scripts/install.sh
```

One repository works the same way. Then start from the workspace root:

```bash
claude
# or
codex
```

## Update

Run the installer again from the same workspace. Files the workflow owns are compared against the current templates. For each one that differs you get a per-file choice:

```text
/path/REC-2130/IMPLEMENTER.md differs from the workflow version.
  [d] diff  [o] overwrite  [k] keep  [a] overwrite all  [s] keep all  [q] abort
Choice [k]:
```

Non-interactive use:

```bash
scripts/install.sh --overwrite-all
scripts/install.sh --keep-all
```

Task state is never touched on update: `TASK_PLAN.md`, `.agent/initial-request.md`, `.agent/review-history.md`, `.agent/reviews/<repository>/review-attempts`, and each repository's `.agent/current-slice.md`. Neither is any repository's own `AGENTS.md` or `CLAUDE.md`. A workspace installed before the attempt counter moved to the workspace root has its counter carried over, not reset.

## Review

Name every repository the slice changed:

```bash
scripts/codex-review.sh service-a service-b
```

Each repository gets its own reviewer, running from that repository's `.agent/`, reading only its uncommitted changes, unable to write. Every repository is validated first, so a bad argument consumes no attempt. Each repository's attempt counter then increments before its reviewer starts, so a crashed or empty review consumes an attempt and never counts as approval. A failed reviewer stops the run, and the repositories after it keep their attempts.

The reviewer's working directory holds only what the reviewer should read: its instructions, the slice, the test output, and the previous review. The run log, the pending review, and the attempt counter sit at the workspace root under `.agent/reviews/<repository>/`. A reviewer that can see its own live run log reads it and spends its context on its own transcript; one that can see the counter learns whether this is its last attempt.

A slice path the reviewer's repository does not have resolves against the workspace root, so a shared `docs/` contract is reachable from a slice while sibling repositories stay off limits.

## Context

One slice runs in one session, and the window has to hold the code, the tests, the review, and a second review attempt. Across three real slices in one workspace, each run ended between 85% and 97% of the model's window with a clean first review, so a second attempt had nowhere to go.

Most of that is the implementer's own output, which no reading rule shrinks. Slice size is the lever, so the review script reports each repository's scope in files and lines before it launches a reviewer. That number is comparable across slices and services, and it is the one honest signal that a slice was too big.

The script also hands back what the caller would otherwise go and read: the review itself on success, and the last 20 lines of the run log when a reviewer dies. Nothing needs to open a run log, and `IMPLEMENTER.md` says not to.

The rest of the rules there follow from the same accounting: edit a file with the editing tool rather than rewriting it through a heredoc, read a doc the slice names once instead of grepping it repeatedly, send test output to a file and keep the tail, keep `TASK_PLAN.md` and the review history to what nothing else carries, and update the plan as the slice goes so a compaction costs nothing.

## Skills

`templates/skills/` is installed into both `.claude/skills/` and `.codex/skills/` on every install. It ships `unslop`, vendored from [cursor/plugins](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md), which strips AI tells from written output. That repository declares no license.

Agents load a skill body only when they invoke it, so the standing context cost is the one-line description. `unslop` is scoped to prose a person reads and tells the agent not to load it while editing code.

Add a skill by dropping `templates/skills/<name>/SKILL.md` into this source repository.

## Development

Installable content lives under `templates/` with `.tmpl` filenames so it cannot act as instructions for this source repository. The skill files keep their real names because no agent scans `templates/` for skills.

```bash
tests/run.sh
```
