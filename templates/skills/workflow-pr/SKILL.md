---
name: workflow-pr
description: Publish explicitly authorized changes after passing checks and clean reviews.
---

# Publish

Require explicit approval for each publishing action, passing checks, and current clean independent reviews for every changed repository. Stop if any gate is missing.

Use the canonical workspace name as `WORK_ITEM`, branch, and exact PR title.

Check the full branch-to-staging diff for unrelated scope. Stage only intended changes; commit and push only as authorized. Never force-push.

Before creating a PR, look for an existing open PR for the same branch and base. Reuse it. Stop on lookup failure; never create duplicates.

Use an absolute `PR_BODY_FILE` and `unslop` for the PR body. Write for a human reviewer with no workflow context. Keep Summary and Tests concise, including important validation omissions. Do not mention slices, workflow state, review attempts, or other workflow internals.

Report the PR URL or failure. Never merge or create promotion PRs. Use `workflow-state` for accepted completion.
