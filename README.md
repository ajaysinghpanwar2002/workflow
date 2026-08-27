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
├── service-a/
│   ├── AGENTS.md              # project owned, never touched
│   ├── CLAUDE.md              # project owned, never touched
│   └── .agent/                # AGENTS.md (reviewer), current-slice.md, review-attempts
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

Task state is never touched on update: `TASK_PLAN.md`, `.agent/initial-request.md`, `.agent/review-history.md`, and each repository's `.agent/current-slice.md` and `.agent/review-attempts`. Neither is any repository's own `AGENTS.md` or `CLAUDE.md`.

## Review

Name every repository the slice changed:

```bash
scripts/codex-review.sh service-a service-b
```

Each repository gets its own reviewer, running from that repository's `.agent/`, reading only its uncommitted changes, unable to write. Every repository is validated first, so a bad argument consumes no attempt. Each repository's attempt counter then increments before its reviewer starts, so a crashed or empty review consumes an attempt and never counts as approval. A failed reviewer stops the run, and the repositories after it keep their attempts.

## Skills

`templates/skills/` is installed into both `.claude/skills/` and `.codex/skills/` on every install. It ships `unslop`, vendored from [cursor/plugins](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md), which strips AI tells from written output. That repository declares no license.

Agents load a skill body only when they invoke it, so the standing context cost is the one-line description. `unslop` is scoped to prose a person reads and tells the agent not to load it while editing code.

Add a skill by dropping `templates/skills/<name>/SKILL.md` into this source repository.

## Development

Installable content lives under `templates/` with `.tmpl` filenames so it cannot act as instructions for this source repository. The skill files keep their real names because no agent scans `templates/` for skills.

```bash
tests/run.sh
```
