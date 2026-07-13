#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

mkdir -p .agent

DIFF_FILE=".agent/current-diff.patch"
SLICE_FILE=".agent/current-slice.md"
PROMPT_FILE=".agent/codex-review-prompt.md"
REVIEW_FILE=".agent/latest-codex-review.md"
PREVIOUS_REVIEW_FILE=".agent/previous-codex-review.md"
TEST_OUTPUT_FILE=".agent/latest-test-output.txt"
TEST_OUTPUT_MAX_LINES=400
REVIEW_WORKDIR="${TMPDIR:-/tmp}/codex-review-workflow"
CODEX_REVIEW_MODEL="${CODEX_REVIEW_MODEL:-gpt-5.6-sol}"
CODEX_REVIEW_REASONING_EFFORT="${CODEX_REVIEW_REASONING_EFFORT:-high}"
CODEX_REVIEW_DRY_RUN="${CODEX_REVIEW_DRY_RUN:-0}"

# The reviewer is a nested `codex exec` call and needs network access, so this
# script cannot run inside a Codex implementer's sandbox. Fail fast with a
# pointer instead of a late, cryptic network error. Commands allowed to run
# outside the sandbox (via .codex/rules/ or an approved escalation) never see
# this variable.
if [ "${CODEX_SANDBOX_NETWORK_DISABLED:-}" = "1" ] && [ "$CODEX_REVIEW_DRY_RUN" != "1" ]; then
  echo "ERROR: running inside a network-disabled Codex sandbox; the nested reviewer cannot reach the API." >&2
  echo "Re-run this script outside the sandbox: request escalated permissions, or make sure the" >&2
  echo "allow rule in .codex/rules/agent-workflow.rules is loaded (the project .codex/ layer must be trusted)." >&2
  exit 2
fi

git diff --binary > "$DIFF_FILE"

if [ ! -s "$DIFF_FILE" ]; then
  echo "No git diff found. Nothing to review." >&2
  exit 1
fi

if [ ! -s "$SLICE_FILE" ]; then
  echo "Missing or empty $SLICE_FILE." >&2
  echo "Write the current slice spec (goal, scope, plan, test command) there first;" >&2
  echo "it is the only plan context the Codex reviewer receives." >&2
  exit 1
fi

# Preserve the previous review so a re-review round can be checked against it.
if [ -s "$REVIEW_FILE" ]; then
  cp "$REVIEW_FILE" "$PREVIOUS_REVIEW_FILE"
fi

mkdir -p "$REVIEW_WORKDIR"

{
  cat prompts/codex-review.md 2>/dev/null || true

  echo
  echo "Repository root for optional read-only inspection: $ROOT"
  echo "Full review history (read-only, if HISTORY_CHECK needs more): $ROOT/.agent/review-history.md"
  echo "Reviewer model: $CODEX_REVIEW_MODEL"
  echo "Reviewer reasoning effort: $CODEX_REVIEW_REASONING_EFFORT"

  echo
  echo "===== CURRENT SLICE SPEC ====="
  cat "$SLICE_FILE"

  echo
  echo "===== PREVIOUS CODEX REVIEW (may be from an earlier slice; absent on first review) ====="
  cat "$PREVIOUS_REVIEW_FILE" 2>/dev/null || true

  echo
  echo "===== LATEST TEST OUTPUT ====="
  if [ -f "$TEST_OUTPUT_FILE" ]; then
    if [ "$(wc -l < "$TEST_OUTPUT_FILE")" -gt "$TEST_OUTPUT_MAX_LINES" ]; then
      echo "(truncated to last $TEST_OUTPUT_MAX_LINES lines)"
    fi
    tail -n "$TEST_OUTPUT_MAX_LINES" "$TEST_OUTPUT_FILE"
  fi

  echo
  echo "===== CURRENT GIT DIFF START ====="
  cat "$DIFF_FILE"
  echo "===== CURRENT GIT DIFF END ====="
} > "$PROMPT_FILE"

if [ "$CODEX_REVIEW_DRY_RUN" = "1" ]; then
  cat "$PROMPT_FILE"
  echo
  echo "Dry run: assembled prompt written to $PROMPT_FILE (codex not invoked)." >&2
  exit 0
fi

codex exec \
  --model "$CODEX_REVIEW_MODEL" \
  --config "model_reasoning_effort=\"$CODEX_REVIEW_REASONING_EFFORT\"" \
  --sandbox read-only \
  --cd "$REVIEW_WORKDIR" \
  --skip-git-repo-check \
  - < "$PROMPT_FILE" | tee "$REVIEW_FILE"

echo
echo "Codex review written to: $REVIEW_FILE"
