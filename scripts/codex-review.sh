#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

mkdir -p .agent

DIFF_FILE=".agent/current-diff.patch"
PROMPT_FILE=".agent/codex-review-prompt.md"
REVIEW_FILE=".agent/latest-codex-review.md"

git diff --binary > "$DIFF_FILE"

if [ ! -s "$DIFF_FILE" ]; then
  echo "No git diff found. Nothing to review." >&2
  exit 1
fi

cat > "$PROMPT_FILE" <<'EOF'
You are reviewing a local code change.

You are read-only.
Do not edit files.
Do not run commands that modify files.
Do not suggest unrelated refactors.

Review the current implementation slice using the context below.
EOF

{
  cat "$PROMPT_FILE"

  echo
  echo "===== AGENTS.md ====="
  cat AGENTS.md 2>/dev/null || true

  echo
  echo "===== TASK_PLAN.md ====="
  cat TASK_PLAN.md 2>/dev/null || true

  echo
  echo "===== ORIGINAL USER REQUEST ====="
  cat .agent/initial-request.md 2>/dev/null || true

  echo
  echo "===== REVIEW HISTORY ====="
  cat .agent/review-history.md 2>/dev/null || true

  echo
  echo "===== LATEST TEST OUTPUT ====="
  cat .agent/latest-test-output.txt 2>/dev/null || true

  echo
  echo "===== REVIEW INSTRUCTIONS ====="
  cat prompts/codex-review.md 2>/dev/null || true

  echo
  echo "===== CURRENT GIT DIFF START ====="
  cat "$DIFF_FILE"
  echo "===== CURRENT GIT DIFF END ====="
} | codex exec --sandbox read-only - | tee "$REVIEW_FILE"

echo
echo "Codex review written to: $REVIEW_FILE"
