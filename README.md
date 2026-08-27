# Agent Workflow

Local implementer workflow with one independent, read-only Codex review per changed Git repository. Workspace mode is recommended, even for one repository.

## Workspace Mode

The workspace root is one work item. It must remain a plain directory: do not initialize it as Git or place it inside another Git repository. Launch Claude Code or interactive Codex from this directory.

Multiple repositories:

```bash
mkdir -p ~/Desktop/sprint-tasks/REC-2130
cd ~/Desktop/sprint-tasks/REC-2130

git clone <service-a-url> service-a
git clone <service-b-url> service-b

/path/to/workflow/scripts/install-workspace-workflow.sh
```

One repository:

```bash
mkdir -p ~/Desktop/sprint-tasks/REC-2130
cd ~/Desktop/sprint-tasks/REC-2130

git clone <service-a-url> service-a

/path/to/workflow/scripts/install-workspace-workflow.sh
```

The workspace name (`REC-2130`) becomes the shared branch name and exact PR title. Ticket branches are based on `staging`, and PRs go from the ticket branch to `staging` only after tests, clean reviews, and explicit user approval.

Each changed repository receives its own review, with at most two attempts per repository per slice:

```bash
scripts/codex-review.sh service-a
scripts/codex-review.sh service-b
```

The installer examines direct children only, preserves project-owned repository-root `AGENTS.md` and `CLAUDE.md`, and installs reviewer instructions under each repository's `.agent/` directory.

Start from the workspace root:

```bash
claude
# or
codex
```

## Legacy Direct-Repository Mode

For backward compatibility, install directly into a repository that does not already have project-owned agent instructions:

```bash
cd service-a
/path/to/workflow/scripts/install-agent-workflow.sh
```

Run its review without an argument:

```bash
scripts/codex-review.sh
```

Direct mode does not derive a ticket branch or PR title from the repository directory name.

## Development

Installable content lives under `templates/` with `.tmpl` filenames so it cannot act as source-repository instructions. Run the portable integration suite with:

```bash
tests/run.sh
```
