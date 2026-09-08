---
name: workflow-review
description: Run independent Codex review after implementation and passing checks.
---

# Review

Update each changed repository's `.agent/current-slice.md` and
`.agent/latest-test-output.txt`. Call the workspace's absolute launcher path
once with every changed direct-child directory name:

```bash
"/absolute/workspace/scripts/codex-review.sh" service-a service-b
```

Use the real path as a standalone command. No shell/env wrapper, pipeline,
redirection, compound command, or direct Codex call.

If sandboxed, request native approval for that exact command before launch
when permitted. The separate Codex process needs service/auth access; reviewer tools stay
read-only. If approval is unavailable or denied, stop and report the command
and blocker. Never bypass restrictions, clear sandbox flags, broaden rules,
or retry a denial another way.

Preflight blocks use no attempt. Started failures and empty reviews do.
Later repositories remain unreviewed after a failure.

Read the printed review, not just the exit code; never open the full run log.
Attempt 1: clean ends review; fix in-scope findings, retest, then attempt 2.
Failed or unclear reviews require user intervention. Attempt 2 must be clean
or the slice is Blocked. Every changed repository needs a current clean
review. Never self-approve, reset attempts, run a third review, or publish here.
