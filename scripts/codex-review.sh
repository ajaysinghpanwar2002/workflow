#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CODEX_REVIEW_MODEL="${CODEX_REVIEW_MODEL:-gpt-5.6-sol}"
CODEX_REVIEW_REASONING_EFFORT="${CODEX_REVIEW_REASONING_EFFORT:-high}"

canonical_git_root() {
  local directory="$1"
  local root
  root="$(git -C "$directory" rev-parse --show-toplevel 2>/dev/null)" || return 1
  (cd "$root" && pwd -P)
}

script_git_root="$(canonical_git_root "$SCRIPT_ROOT")" || script_git_root=""

if [ -n "$script_git_root" ]; then
  if [ "$script_git_root" != "$SCRIPT_ROOT" ]; then
    echo "The installed script root is inside another Git repository: $SCRIPT_ROOT" >&2
    exit 1
  fi
  if [ "$#" -ne 0 ]; then
    echo "Direct-repository mode accepts no repository argument." >&2
    exit 1
  fi
  REPO_ROOT="$SCRIPT_ROOT"
else
  if [ "$#" -ne 1 ]; then
    echo "Workspace mode requires exactly one direct child repository argument." >&2
    exit 1
  fi
  case "$1" in
    ''|'.'|'..'|*/*)
      echo "Repository must be the name of one direct child directory." >&2
      exit 1
      ;;
  esac

  candidate="$SCRIPT_ROOT/$1"
  if [ ! -d "$candidate" ]; then
    echo "Repository is not a direct child directory: $1" >&2
    exit 1
  fi
  resolved_candidate="$(cd "$candidate" && pwd -P)"
  if [ "$(dirname "$resolved_candidate")" != "$SCRIPT_ROOT" ]; then
    echo "Repository resolves outside the workspace: $1" >&2
    exit 1
  fi
  repository_git_root="$(canonical_git_root "$resolved_candidate")" || {
    echo "Selected child is not a Git repository: $1" >&2
    exit 1
  }
  if [ "$repository_git_root" != "$resolved_candidate" ]; then
    echo "Selected child is not exactly a Git repository root: $1" >&2
    exit 1
  fi
  REPO_ROOT="$resolved_candidate"
fi

REVIEW_CWD="$REPO_ROOT/.agent"
REVIEWER_INSTRUCTIONS="$REVIEW_CWD/AGENTS.md"
SLICE_FILE="$REVIEW_CWD/current-slice.md"
ATTEMPT_FILE="$REVIEW_CWD/review-attempts"
REVIEW_FILE="$REVIEW_CWD/latest-codex-review.md"
PREVIOUS_REVIEW_FILE="$REVIEW_CWD/previous-codex-review.md"
PENDING_REVIEW_FILE="$REVIEW_CWD/pending-codex-review.md"
RUN_LOG="$REVIEW_CWD/latest-codex-review-run.log"

if [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
  echo "No staged, unstaged, or untracked changes found in: $REPO_ROOT" >&2
  exit 1
fi

if [ ! -f "$REVIEWER_INSTRUCTIONS" ]; then
  echo "Missing reviewer instructions: $REVIEWER_INSTRUCTIONS" >&2
  exit 1
fi

if [ ! -f "$SLICE_FILE" ]; then
  echo "Missing current slice: $SLICE_FILE" >&2
  exit 1
fi

slice_details="$(sed \
  -e '/^[[:space:]]*$/d' \
  -e '/^[[:space:]]*# Slice[[:space:]]*$/d' \
  -e '/^[[:space:]]*Goal:[[:space:]]*$/d' \
  -e '/^[[:space:]]*Scope:[[:space:]]*$/d' \
  -e '/^[[:space:]]*Out:[[:space:]]*$/d' \
  -e '/^[[:space:]]*Tests:[[:space:]]*$/d' \
  -e '/^[[:space:]]*Contract:[[:space:]]*$/d' \
  "$SLICE_FILE")"
if ! printf '%s' "$slice_details" | grep -q '[^[:space:]]'; then
  echo "Current slice contains only empty template headings: $SLICE_FILE" >&2
  exit 1
fi

if [ -e "$ATTEMPT_FILE" ]; then
  attempt_count="$(sed -n '1,$p' "$ATTEMPT_FILE")"
else
  attempt_count="0"
fi

case "$attempt_count" in
  0|1|2) ;;
  *)
    echo "Invalid review attempt counter; expected exactly 0, 1, or 2: $ATTEMPT_FILE" >&2
    exit 1
    ;;
esac

if [ "$attempt_count" -eq 2 ]; then
  echo "Review limit reached for this slice: 2/2." >&2
  echo "Mark the task Blocked and ask the user to intervene." >&2
  exit 1
fi

if [ "${CODEX_SANDBOX_NETWORK_DISABLED:-}" = "1" ]; then
  echo "ERROR: running inside a network-disabled Codex implementer sandbox." >&2
  echo "Run the installed review script through its project-scoped allow rule." >&2
  exit 2
fi

# Clear stale approval artifacts only after every validation has passed.
if [ -s "$REVIEW_FILE" ]; then
  mv "$REVIEW_FILE" "$PREVIOUS_REVIEW_FILE"
fi
rm -f "$REVIEW_FILE" "$PENDING_REVIEW_FILE"

next_attempt=$((attempt_count + 1))
attempt_temp="$(mktemp "$REVIEW_CWD/.review-attempts.XXXXXX")"
cleanup_attempt_temp() {
  rm -f "$attempt_temp"
}
trap cleanup_attempt_temp EXIT HUP INT TERM
printf '%s\n' "$next_attempt" >"$attempt_temp"
mv "$attempt_temp" "$ATTEMPT_FILE"
trap - EXIT HUP INT TERM

printf 'Codex review attempt %s/2\n' "$next_attempt"

status=0
codex exec \
  --model "$CODEX_REVIEW_MODEL" \
  --config "review_model=\"$CODEX_REVIEW_MODEL\"" \
  --config "model_reasoning_effort=\"$CODEX_REVIEW_REASONING_EFFORT\"" \
  --sandbox read-only \
  --cd "$REVIEW_CWD" \
  --ephemeral \
  --color never \
  --output-last-message "$PENDING_REVIEW_FILE" \
  review --uncommitted >"$RUN_LOG" 2>&1 || status=$?

review_failed() {
  rm -f "$PENDING_REVIEW_FILE" "$REVIEW_FILE"
  echo "ERROR: $1" >&2
  echo "This review attempt was consumed and is not approval. See: $RUN_LOG" >&2
}

if [ "$status" -ne 0 ]; then
  review_failed "the Codex reviewer exited with status $status."
  exit "$status"
fi

if [ ! -s "$PENDING_REVIEW_FILE" ] || ! grep -q '[^[:space:]]' "$PENDING_REVIEW_FILE"; then
  review_failed "the Codex reviewer produced no review text."
  exit 3
fi

mv "$PENDING_REVIEW_FILE" "$REVIEW_FILE"
printf 'Codex review written to: %s\n' "$REVIEW_FILE"
