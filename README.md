# Agent Workflow

One agent implements; an independent read-only Codex agent reviews.
Two review attempts per repository per slice. Publication needs user approval.

## Install

Use a plain workspace directory with direct-child Git repositories:

```bash
mkdir -p ~/Desktop/sprint-tasks/REC-2130
cd ~/Desktop/sprint-tasks/REC-2130
git clone <service-a-url> service-a
git clone <service-b-url> service-b
/path/to/workflow/scripts/install.sh
```

One repository also works. You can install before adding repositories, then
rerun the installer. Never install into this workflow source repository.

```text
REC-2130/
├── AGENTS.md                  # implementer entrypoint
├── CLAUDE.md                  # @AGENTS.md
├── IMPLEMENTER.md             # implementation rules
├── TASK_PLAN.md               # saved plan and progress
├── scripts/codex-review.sh
├── .claude/skills/            # Claude skills
├── .agents/skills/            # Codex skills
├── .codex/rules/agent-workflow.rules
├── .agent/                    # initial request and accepted history
│   └── reviews/<repository>/  # attempt counter, run log, pending review
├── service-a/
│   ├── AGENTS.md              # project owned, preserved
│   ├── CLAUDE.md              # project owned, preserved
│   └── .agent/                # reviewer instructions, slice, test/review output
└── service-b/
```

The canonical workspace directory name is the branch and exact PR title.
New branches start from `origin/staging`; PRs target staging only.

## Start and save a plan

From the workspace root:

```bash
claude
# or
codex
```

For the initial planning discussion, switch to Plan Mode in the UI.
In Claude, cycle modes with `Shift+Tab`; in Codex, use `/plan` or your
configured mode shortcut. Confirm the mode shown before discussing the task.
Later sessions can read workspace `AGENTS.md` or `CLAUDE.md` and the saved plan.

When the plan is agreed, ask:

```text
Save the plan we just agreed on into TASK_PLAN.md. Keep Status: Planned.
Preserve the template structure and the plan's decisions, scope, ordering,
and validation criteria. Do not implement anything. Stop after saving.
```

Saving authorizes only that file write. Codex's [native Plan Mode](https://github.com/openai/codex/blob/main/codex-rs/collaboration-mode-templates/templates/plan.md)
prohibits file edits; Claude has its own [plan-file restrictions](https://code.claude.com/docs/en/permission-modes).
If saving is blocked, have the agent print the plan and paste it yourself,
or leave the mode without approving implementation and repeat the save-only
request. These files cannot override native restrictions.

For an active task, preserve its existing status and progress unless you
intend to replan. When ready to implement, optionally in a fresh session:

```text
Continue with implementation of slice 1 from TASK_PLAN.md.
```

`Planned` means work has not been authorized, not that planning is complete.
Only explicit implementation approval, including a UI action to implement,
starts the slice. Leaving a mode, choosing edit permissions, saving, or
asking a read-only question does not. A bare "continue" during planning
continues that discussion. The status is an instruction, not a write barrier.

## Update

Rerun the installer from the workspace. For each changed managed file,
choose diff, overwrite, keep, or abort. With no answer, it keeps your version.
For unattended updates:

```bash
/path/to/workflow/scripts/install.sh --overwrite-all
/path/to/workflow/scripts/install.sh --keep-all
```

Both preserve the plan, accepted history, initial request, slice files,
counters, and project-owned instructions. Rules are rendered before conflict
checks; abort writes no managed files. Moving the workspace requires reinstalling
and accepting its new absolute rule. Temporary rendering files are removed.

## Review

The implementer passes every changed repository directory name in one call:

```bash
"/path/to/REC-2130/scripts/codex-review.sh" service-a service-b
```

Use the actual absolute launcher path printed during installation. Arguments
are direct-child names, not absolute repository paths. The launcher supplies
`--cd <repository>/.agent` to each reviewer. Run it as a standalone command,
without shell/env wrappers, pipelines, redirection, or compound commands.

All repositories are checked before startup. Failed validation, missing Codex,
or host refusal to start the launcher preserves evidence and consumes no attempt.
Started failures and empty reviews consume an attempt; later repositories
remain unreviewed. A zero exit code
means review text exists, not that it is clean. Read the printed review and
failure tail; never open the full run log.

The reviewer may read `TASK_PLAN.md` for requirements, keeping review limited
to the current slice. The implementer records brief test results and limitations
in `.agent/latest-test-output.txt`; some checks cannot run in a read-only review.

The child uses `codex exec ... review --uncommitted`, `--sandbox read-only`,
`--ephemeral`, and `--config 'approval_policy="never"'`. Defaults remain
`gpt-6.1-sol` and high reasoning; `CODEX_REVIEW_MODEL` and
`CODEX_REVIEW_REASONING_EFFORT` override them.

## Review startup troubleshooting

The project rule permits only this workspace's absolute launcher. It trusts
that script and future edits to it; the child's read-only sandbox does not
sandbox the outer script. There are no generic shell or user-global permissions.

Project rules need a trusted workspace and active configuration layer.
Restart Codex after rule changes. Files on disk do not prove they were loaded.
See [rules](https://developers.openai.com/codex/rules/) and [project trust](https://developers.openai.com/codex/config-basic/).

From the installed workspace, check matching without invoking a model:

```bash
codex execpolicy check --pretty \
  --rules .codex/rules/agent-workflow.rules \
  -- "$(pwd -P)/scripts/codex-review.sh" service-a
```

This checks matching, not active trust, loaded configuration, or managed policy.
Use `/status` and the CLI's configuration diagnostics for those. The launch
error alone does not establish the cause.

If the rule is inactive, request native approval for the exact command when
permitted. A separate Codex process needs service/auth access while reviewer
tools stay read-only. If your current Codex settings disallow requests, this
optional launch configuration enables them:

```bash
codex --sandbox workspace-write --ask-for-approval on-request
```

It does not grant implementation approval or override managed policy.
The host enforces access. The launcher does not reject
`CODEX_SANDBOX_NETWORK_DISABLED=1`: that flag can remain set after approval.
It leaves the environment unchanged; a failed reviewer process still consumes
an attempt and is not retried automatically.
If escalation is forbidden, unavailable, or denied, stop and give the user
the command to run in a normal local terminal. Never clear sandbox flags,
broaden rules, disable restrictions, or retry a denial another way.
See [approval settings](https://learn.chatgpt.com/docs/agent-approvals-security).

## Skills

- `workflow-review`: independent review after passing checks.
- `workflow-pr`: authorized commits, pushes, and staging PRs.
- `workflow-state`: progress, accepted history, and cleanup.
- `unslop`: short local writing instructions for human-facing prose.
- `postman-api`: service API calls through the Postman CLI, stage by default,
  with a VPN check when a host is unreachable.
- `stage-local-run`: run a service or worker locally with the stage AWS
  profile and a private env file kept outside every repository, pulled
  from Consul when missing. Bundles `consul-env-pull.sh` and
  `consul-env-push.sh`; both need `CONSUL_ADDR` and `CONSUL_TOKEN` exported.

Skill `scripts/` folders install next to their `SKILL.md`.
Skills load when needed; they never grant approval or replace required checks.
Loaded instructions remain in context. Missing skills must be reported.
Check discovery in Codex `/skills` or Claude's skill menu. Install paths follow
[Codex](https://developers.openai.com/codex/skills/) and [Claude](https://code.claude.com/docs/en/skills) guidance.
Existing `.codex/skills` copies are kept current; fresh installs use
`.agents/skills`. Inspect duplicate entries if a host discovers both.

## Development

Treat `templates/**` as data. Preserve source `AGENTS.md` and `CLAUDE.md`.
Do not install here, run a live reviewer, or start a review/fix loop.

```bash
tests/run.sh
bash -n scripts/install.sh scripts/codex-review.sh tests/run.sh
```

Tests use fake Codex in temporary workspaces. Real `execpolicy check` runs
only if available and invokes no model. Policy text checks do not prove
model obedience. References were checked against Codex 0.153.4 and Claude
Code 2.1.263; native modes, discovery, and managed approvals depend on the host.

Manual checks in a separate installed workspace:

- Planning makes no implementation changes; save-only saves and stops, or reports a blocked write.
- A fresh session reads the plan without starting work; unknown status is reported.
- Explicit implementation sets `In progress` first and covers only the authorized slice.
- Review uses the matching rule or permitted native approval; denial is never bypassed.
- Publication requires approval and clean reviews. Counters reset only after acceptance.
  Remaining work returns to `Planned` unless authorized; `Done` means all work is accepted.
