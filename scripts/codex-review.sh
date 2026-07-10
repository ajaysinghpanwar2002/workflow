#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

mkdir -p .agent

DIFF_FILE=".agent/current-diff.patch"
PROMPT_FILE=".agent/codex-review-prompt.md"
REVIEW_FILE=".agent/latest-codex-review.md"
REVIEW_WORKDIR="${TMPDIR:-/tmp}/codex-review-workflow"
CODEX_REVIEW_MODEL="${CODEX_REVIEW_MODEL:-gpt-5.6-sol}"
CODEX_REVIEW_REASONING_EFFORT="${CODEX_REVIEW_REASONING_EFFORT:-high}"

git diff --binary > "$DIFF_FILE"

if [ ! -s "$DIFF_FILE" ]; then
  echo "No git diff found. Nothing to review." >&2
  exit 1
fi

mkdir -p "$REVIEW_WORKDIR"

cat > "$PROMPT_FILE" <<'EOF'
You are reviewing a local code change.

You are the separate Codex reviewer process launched by scripts/codex-review.sh.
You are read-only in this process.
Do not edit files.
Do not run commands that modify files.
Do not suggest unrelated refactors.

Review the current implementation slice using the context below.
EOF

{
  cat "$PROMPT_FILE"

  echo
  echo "Repository root for optional read-only inspection: $ROOT"
  echo "Reviewer model: $CODEX_REVIEW_MODEL"
  echo "Reviewer reasoning effort: $CODEX_REVIEW_REASONING_EFFORT"

  echo
  echo "===== IMPLEMENTER.md ====="
  cat IMPLEMENTER.md 2>/dev/null || true

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
} | codex exec \
  --model "$CODEX_REVIEW_MODEL" \
  --config "model_reasoning_effort=\"$CODEX_REVIEW_REASONING_EFFORT\"" \
  --sandbox read-only \
  --cd "$REVIEW_WORKDIR" \
  --skip-git-repo-check \
  - | tee "$REVIEW_FILE"

echo
echo "Codex review written to: $REVIEW_FILE"
