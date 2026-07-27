#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

mkdir -p .agent

SLICE_FILE=".agent/current-slice.md"
REVIEW_FILE=".agent/latest-codex-review.md"
PREVIOUS_REVIEW_FILE=".agent/previous-codex-review.md"
PENDING_REVIEW_FILE=".agent/pending-codex-review.md"
CODEX_REVIEW_MODEL="${CODEX_REVIEW_MODEL:-gpt-5.6-sol}"
CODEX_REVIEW_REASONING_EFFORT="${CODEX_REVIEW_REASONING_EFFORT:-high}"

# The reviewer is a nested `codex exec review` call and needs network access, so this
# script cannot run inside a Codex implementer's sandbox. Fail fast with a
# pointer instead of a late, cryptic network error. Commands allowed to run
# outside the sandbox (via .codex/rules/ or an approved escalation) never see
# this variable.
if [ "${CODEX_SANDBOX_NETWORK_DISABLED:-}" = "1" ]; then
  echo "ERROR: running inside a network-disabled Codex sandbox; the nested reviewer cannot reach the API." >&2
  echo "Re-run this script outside the sandbox: request escalated permissions, or make sure the" >&2
  echo "allow rule in .codex/rules/agent-workflow.rules is loaded (the project .codex/ layer must be trusted)." >&2
  exit 2
fi

if [ -z "$(git status --porcelain)" ]; then
  echo "No staged, unstaged, or untracked changes found. Nothing to review." >&2
  exit 1
fi

if [ ! -s "$SLICE_FILE" ]; then
  echo "Missing or empty $SLICE_FILE." >&2
  echo "Write the current slice spec (goal, scope, plan, test command) there first;" >&2
  echo "the reviewer reads it from the repository to learn what the slice was meant to do." >&2
  exit 1
fi

# Leftovers from the removed prompt-assembly flow. Delete them so nobody
# mistakes them for input the reviewer still consumes.
rm -f .agent/current-diff.patch .agent/codex-review-prompt.md

# Fail closed: keep the last completed review for reference, then clear
# REVIEW_FILE so a stale review can never be read as this run's result.
if [ -s "$REVIEW_FILE" ]; then
  mv "$REVIEW_FILE" "$PREVIOUS_REVIEW_FILE"
fi
rm -f "$REVIEW_FILE" "$PENDING_REVIEW_FILE"

# Codex's dedicated review mode picks the uncommitted changes itself and brings
# its own review prompt. It runs read-only in this repository, so it can inspect
# surrounding code, tests, and docs for context.
status=0
codex exec \
  --model "$CODEX_REVIEW_MODEL" \
  --config "model_reasoning_effort=\"$CODEX_REVIEW_REASONING_EFFORT\"" \
  --sandbox read-only \
  --cd "$ROOT" \
  --ephemeral \
  --color never \
  --output-last-message "$PENDING_REVIEW_FILE" \
  review --uncommitted || status=$?

review_failed() {
  rm -f "$PENDING_REVIEW_FILE"
  echo >&2
  echo "ERROR: $1" >&2
  echo "This is a review failure, not an approval. $REVIEW_FILE was not written" >&2
  echo "and any earlier review is kept at $PREVIOUS_REVIEW_FILE." >&2
  echo "Mark the task blocked and stop for the user." >&2
}

if [ "$status" -ne 0 ]; then
  review_failed "the Codex reviewer exited with status $status; no review was produced."
  exit "$status"
fi

if [ ! -s "$PENDING_REVIEW_FILE" ]; then
  review_failed "the Codex reviewer finished but produced no final review text."
  exit 3
fi

mv "$PENDING_REVIEW_FILE" "$REVIEW_FILE"

echo
echo "Codex review written to: $REVIEW_FILE"
echo "Read the prose and decide: findings -> fix, retest, review again; clearly clean -> stop"
echo "for user review; ambiguous, truncated, or empty -> blocked, never self-approve."
