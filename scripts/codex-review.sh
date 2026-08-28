#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CODEX_REVIEW_MODEL="${CODEX_REVIEW_MODEL:-gpt-5.6-sol}"
CODEX_REVIEW_REASONING_EFFORT="${CODEX_REVIEW_REASONING_EFFORT:-high}"

usage() {
  cat >&2 <<'USAGE'
Usage: codex-review.sh <repository> [<repository> ...]

Pass every direct child repository you changed in this slice. Each one gets its
own reviewer, attempt counter, and review file. All repositories are validated
before the first reviewer starts. If a reviewer fails, the repositories after it
are not reviewed and keep their attempts.
USAGE
}

canonical_git_root() {
  local directory="$1"
  local root
  root="$(git -C "$directory" rev-parse --show-toplevel 2>/dev/null)" || return 1
  (cd "$root" && pwd -P)
}

# Every path this script touches for one repository. The reviewer works from
# REVIEW_CWD, so only files it should read live there. Harness state lives under
# the workspace root, out of its sight: a reviewer that reads its own live run
# log burns its context on its own transcript, and a reviewer that reads the
# attempt counter learns whether this is its last chance.
set_repository_paths() {
  local repository="$1"
  local name="$2"

  REVIEW_CWD="$repository/.agent"
  REVIEWER_INSTRUCTIONS="$REVIEW_CWD/AGENTS.md"
  SLICE_FILE="$REVIEW_CWD/current-slice.md"
  REVIEW_FILE="$REVIEW_CWD/latest-codex-review.md"
  PREVIOUS_REVIEW_FILE="$REVIEW_CWD/previous-codex-review.md"

  RUN_DIR="$SCRIPT_ROOT/.agent/reviews/$name"
  ATTEMPT_FILE="$RUN_DIR/review-attempts"
  PENDING_REVIEW_FILE="$RUN_DIR/pending-codex-review.md"
  RUN_LOG="$RUN_DIR/latest-codex-review-run.log"
}

# Workspaces installed while the counter still lived in the reviewer's
# directory. Carry it over instead of silently restarting at 0.
migrate_attempt_counter() {
  local legacy="$REVIEW_CWD/review-attempts"

  [ -f "$legacy" ] || return 0

  mkdir -p "$RUN_DIR"
  if [ -e "$ATTEMPT_FILE" ]; then
    rm -f "$legacy"
  else
    mv "$legacy" "$ATTEMPT_FILE"
  fi
}

# Sets RESOLVED_REPOSITORY. Called as a statement so a bad name can exit.
resolve_repository() {
  local name="$1"

  case "$name" in
    ''|'.'|'..'|*/*)
      echo "Repository must be the name of one direct child directory: $name" >&2
      exit 1
      ;;
  esac

  local candidate="$SCRIPT_ROOT/$name"
  if [ ! -d "$candidate" ]; then
    echo "Repository is not a direct child directory: $name" >&2
    exit 1
  fi

  local repository
  repository="$(cd "$candidate" && pwd -P)"
  if [ "$(dirname "$repository")" != "$SCRIPT_ROOT" ]; then
    echo "Repository resolves outside the workspace: $name" >&2
    exit 1
  fi

  local git_root
  git_root="$(canonical_git_root "$repository")" || {
    echo "Selected child is not a Git repository: $name" >&2
    exit 1
  }
  if [ "$git_root" != "$repository" ]; then
    echo "Selected child is not exactly a Git repository root: $name" >&2
    exit 1
  fi

  RESOLVED_REPOSITORY="$repository"
}

# Sets ATTEMPT_COUNT from the paths already set. Called as a statement so an
# unusable counter can exit before any reviewer starts.
read_attempt_count() {
  local name="$1"

  if [ -e "$ATTEMPT_FILE" ]; then
    ATTEMPT_COUNT="$(sed -n '1,$p' "$ATTEMPT_FILE")"
  else
    ATTEMPT_COUNT="0"
  fi

  case "$ATTEMPT_COUNT" in
    0|1|2) ;;
    *)
      echo "Invalid review attempt counter for $name; expected exactly 0, 1, or 2: $ATTEMPT_FILE" >&2
      exit 1
      ;;
  esac
}

validate_repository() {
  local repository="$1"
  local name="$2"

  set_repository_paths "$repository" "$name"
  migrate_attempt_counter

  if [ -z "$(git -C "$repository" status --porcelain)" ]; then
    echo "No staged, unstaged, or untracked changes found in $name: $repository" >&2
    echo "Pass only the repositories this slice changed." >&2
    exit 1
  fi

  if [ ! -f "$REVIEWER_INSTRUCTIONS" ]; then
    echo "Missing reviewer instructions for $name: $REVIEWER_INSTRUCTIONS" >&2
    exit 1
  fi

  if [ ! -f "$SLICE_FILE" ]; then
    echo "Missing current slice for $name: $SLICE_FILE" >&2
    exit 1
  fi

  local slice_details
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
    echo "Current slice for $name contains only empty template headings: $SLICE_FILE" >&2
    exit 1
  fi

  read_attempt_count "$name"

  if [ "$ATTEMPT_COUNT" -eq 2 ]; then
    echo "Review limit reached for this slice: 2/2 in $name." >&2
    echo "Mark the task Blocked and ask the user to intervene." >&2
    exit 1
  fi
}

review_failed() {
  rm -f "$PENDING_REVIEW_FILE" "$REVIEW_FILE"
  echo "ERROR in $1: $2" >&2
  echo "This review attempt was consumed and is not approval." >&2

  # The reason a reviewer died is at the end of its log. Print that much so the
  # caller never opens the log itself: it holds the reviewer's whole transcript.
  if [ -s "$RUN_LOG" ]; then
    echo "Last 20 lines of $RUN_LOG:" >&2
    tail -20 "$RUN_LOG" >&2
  fi
}

# The size of what the reviewer is about to read. A slice that needs a large
# diff to reach its first review has no room left for a second attempt.
set_review_scope() {
  local repository="$1"
  local file

  SCOPE_FILES=$((
    $(git -C "$repository" diff --name-only HEAD 2>/dev/null | wc -l) +
    $(git -C "$repository" ls-files --others --exclude-standard | wc -l)
  ))
  SCOPE_LINES="$(git -C "$repository" diff --numstat HEAD 2>/dev/null |
    awk '{ added += $1; removed += $2 } END { print added + removed + 0 }')"

  # numstat covers tracked files only, and a slice is mostly new files.
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    SCOPE_LINES=$((SCOPE_LINES + $(wc -l <"$repository/$file" 2>/dev/null || echo 0)))
  done <<UNTRACKED
$(git -C "$repository" ls-files --others --exclude-standard)
UNTRACKED
}

review_repository() {
  local repository="$1"
  local name="$2"
  local status=0

  set_repository_paths "$repository" "$name"
  read_attempt_count "$name"
  mkdir -p "$RUN_DIR"

  # Clear stale approval artifacts only after every validation has passed.
  if [ -s "$REVIEW_FILE" ]; then
    mv "$REVIEW_FILE" "$PREVIOUS_REVIEW_FILE"
  fi
  rm -f "$REVIEW_FILE" "$PENDING_REVIEW_FILE"

  # Left behind by a workspace that ran these into the reviewer's directory.
  rm -f "$REVIEW_CWD/latest-codex-review-run.log" "$REVIEW_CWD/pending-codex-review.md"

  LAST_ATTEMPT=$((ATTEMPT_COUNT + 1))
  ATTEMPT_TEMP="$(mktemp "$RUN_DIR/.review-attempts.XXXXXX")"
  trap 'rm -f "$ATTEMPT_TEMP"' EXIT HUP INT TERM
  printf '%s\n' "$LAST_ATTEMPT" >"$ATTEMPT_TEMP"
  mv "$ATTEMPT_TEMP" "$ATTEMPT_FILE"
  trap - EXIT HUP INT TERM

  set_review_scope "$repository"
  printf '\n%s: Codex review attempt %s/2, %s files and %s lines under review\n' \
    "$name" "$LAST_ATTEMPT" "$SCOPE_FILES" "$SCOPE_LINES"

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

  if [ "$status" -ne 0 ]; then
    review_failed "$name" "the Codex reviewer exited with status $status."
    return "$status"
  fi

  if [ ! -s "$PENDING_REVIEW_FILE" ] || ! grep -q '[^[:space:]]' "$PENDING_REVIEW_FILE"; then
    review_failed "$name" "the Codex reviewer produced no review text."
    return 3
  fi

  mv "$PENDING_REVIEW_FILE" "$REVIEW_FILE"
  printf '%s: review written to %s\n' "$name" "$REVIEW_FILE"

  # The caller has to act on this, so hand it over instead of making it read the
  # file back.
  printf -- '--- %s review ---\n' "$name"
  cat "$REVIEW_FILE"
  # A last message from the reviewer does not always end in a newline.
  [ -z "$(tail -c 1 "$REVIEW_FILE")" ] || printf '\n'
  printf -- '--- end of %s review ---\n' "$name"
  return 0
}

if git -C "$SCRIPT_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "The workspace root must not be a Git repository or inside one: $SCRIPT_ROOT" >&2
  exit 1
fi

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

# Pass one resolves and validates every repository. Nothing runs and no attempt
# is consumed until all of them are reviewable.
repository_names=()
repository_roots=()
for argument in "$@"; do
  resolve_repository "$argument"
  for existing in ${repository_roots[@]+"${repository_roots[@]}"}; do
    if [ "$existing" = "$RESOLVED_REPOSITORY" ]; then
      echo "Repository listed more than once: $argument" >&2
      exit 1
    fi
  done
  validate_repository "$RESOLVED_REPOSITORY" "$argument"
  repository_names+=("$argument")
  repository_roots+=("$RESOLVED_REPOSITORY")
done

if [ "${CODEX_SANDBOX_NETWORK_DISABLED:-}" = "1" ]; then
  echo "ERROR: running inside a network-disabled Codex implementer sandbox." >&2
  echo "Run the installed review script through its project-scoped allow rule." >&2
  exit 2
fi

# Pass two reviews one repository at a time and stops at the first failure so
# the repositories after it keep their attempts.
total="${#repository_roots[@]}"
summary=()
LAST_ATTEMPT=0
exit_status=0
index=0
while [ "$index" -lt "$total" ]; do
  name="${repository_names[$index]}"
  repository_status=0
  review_repository "${repository_roots[$index]}" "$name" || repository_status=$?

  if [ "$repository_status" -eq 0 ]; then
    summary+=("$name: review written, attempt $LAST_ATTEMPT/2")
  else
    summary+=("$name: reviewer failed, attempt $LAST_ATTEMPT/2 consumed")
    exit_status="$repository_status"
    index=$((index + 1))
    break
  fi

  index=$((index + 1))
done

while [ "$index" -lt "$total" ]; do
  summary+=("${repository_names[$index]}: not reviewed, attempts untouched")
  index=$((index + 1))
done

# One repository already reported itself line by line.
if [ "$total" -gt 1 ]; then
  printf '\nSummary:\n'
  for line in "${summary[@]}"; do
    printf '%s\n' "- $line"
  done
fi

exit "$exit_status"
