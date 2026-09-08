---
name: workflow-pr
description: Publish explicitly authorized changes after passing checks and clean reviews.
---

# Publish

Require explicit approval for each publishing action, passing checks, and
current clean independent reviews for every changed repository. Stop if missing.

Use the canonical workspace name as `WORK_ITEM`, branch, and exact PR title.
Check the full branch-to-staging diff for unrelated scope. Stage only intended
changes; commit and push only as authorized. Never force-push.

In each repository, look up the open PR first. Reuse it; lookup failure is
an error.

```bash
gh pr list --head "$WORK_ITEM" --base staging --state open --json url --jq '.[0].url // empty'
```

Create only after a successful empty lookup:

```bash
gh pr create --base staging --head "$WORK_ITEM" --title "$WORK_ITEM" --body-file "$PR_BODY_FILE"
```

Use an absolute `PR_BODY_FILE`. Keep Summary, Tests, and Review sections short:
behavior change; checks and outcomes, including omissions; "Codex clean after
attempt N/2" only when true. No transcripts.

Report the URL or failure. Never create duplicates, merge, target release or
master, or create promotion PRs. Use `workflow-state` for accepted completion.
