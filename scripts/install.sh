#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORKSPACE_ROOT="$(pwd -P)"

CONFLICT_POLICY="ask"

usage() {
  cat >&2 <<'USAGE'
Usage: install.sh [--overwrite-all | --keep-all]

Installs the agent workflow into the current directory, which must be a plain
directory holding one or more direct child Git repositories.

Re-running updates the workflow. For each managed file that differs, you are
asked per file whether to overwrite, keep, or show the diff.

  --overwrite-all  Replace every differing managed file without asking.
  --keep-all       Keep every differing managed file without asking.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --overwrite-all) CONFLICT_POLICY="overwrite" ;;
    --keep-all) CONFLICT_POLICY="keep" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if git -C "$WORKSPACE_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "The workspace root must be a plain directory, not a Git repository or a directory inside one: $WORKSPACE_ROOT" >&2
  exit 1
fi

repositories=()
for candidate in "$WORKSPACE_ROOT"/*; do
  [ -d "$candidate" ] || continue

  git_root="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null)" || continue
  candidate_root="$(cd "$candidate" && pwd -P)"
  resolved_git_root="$(cd "$git_root" && pwd -P)"

  if [ "$candidate_root" != "$resolved_git_root" ]; then
    echo "Direct child is inside a Git repository but is not its root: $candidate" >&2
    exit 1
  fi

  if [ "$(dirname "$candidate_root")" != "$WORKSPACE_ROOT" ]; then
    echo "Repository child resolves outside the workspace: $candidate" >&2
    exit 1
  fi

  if [ "$candidate_root" = "$SOURCE_ROOT" ]; then
    continue
  fi

  repositories+=("$candidate_root")
done

if [ "${#repositories[@]}" -eq 0 ]; then
  echo "No direct child Git repositories found in: $WORKSPACE_ROOT" >&2
  exit 1
fi

# Managed files are owned by the workflow and are replaced on update.
# Mutable files hold task state and are created once, never touched again.
managed_sources=()
managed_targets=()
managed_actions=()
created_count=0
updated_count=0
unchanged_count=0
kept_files=()

show_diff() {
  local current="$1"
  local incoming="$2"
  if command -v diff >/dev/null 2>&1; then
    printf -- '-- lines your version has, ++ lines the workflow version has\n'
    diff -u "$current" "$incoming" || true
  else
    echo "diff is unavailable; cannot show the change." >&2
  fi
}

# Sets ASK_RESULT to overwrite, keep, or abort. A global is required because
# "overwrite all" and "keep all" must outlive the call.
ASK_RESULT=""
ask_conflict() {
  local target="$1"
  local source_file="$2"
  local answer

  while :; do
    printf '\n%s differs from the workflow version.\n' "$target" >&2
    printf '  [d] diff  [o] overwrite  [k] keep  [a] overwrite all  [s] keep all  [q] abort\n' >&2
    printf 'Choice [k]: ' >&2
    if ! IFS= read -r answer; then
      printf '\n' >&2
      answer=""
    fi
    case "$answer" in
      d|D) show_diff "$target" "$source_file" >&2 ;;
      o|O) ASK_RESULT="overwrite"; return 0 ;;
      k|K|"") ASK_RESULT="keep"; return 0 ;;
      a|A) CONFLICT_POLICY="overwrite"; ASK_RESULT="overwrite"; return 0 ;;
      s|S) CONFLICT_POLICY="keep"; ASK_RESULT="keep"; return 0 ;;
      q|Q) ASK_RESULT="abort"; return 0 ;;
      *) printf 'Answer d, o, k, a, s, or q.\n' >&2 ;;
    esac
  done
}

# Pass one records an action for every managed file and fails before any write.
plan_managed() {
  local source_file="$1"
  local target="$2"
  local action

  if [ -L "$target" ] || { [ -e "$target" ] && [ ! -f "$target" ]; }; then
    echo "Refusing to replace a symlink or non-regular file: $target" >&2
    exit 1
  fi

  if [ ! -e "$target" ]; then
    action="create"
  elif cmp -s "$source_file" "$target"; then
    action="unchanged"
  else
    case "$CONFLICT_POLICY" in
      overwrite) action="overwrite" ;;
      keep) action="keep" ;;
      *)
        ask_conflict "$target" "$source_file"
        action="$ASK_RESULT"
        ;;
    esac

    if [ "$action" = "abort" ]; then
      echo "Aborted. Nothing was written." >&2
      exit 1
    fi
  fi

  managed_sources+=("$source_file")
  managed_targets+=("$target")
  managed_actions+=("$action")
}

apply_managed() {
  local index=0
  local total="${#managed_targets[@]}"

  while [ "$index" -lt "$total" ]; do
    local source_file="${managed_sources[$index]}"
    local target="${managed_targets[$index]}"
    local action="${managed_actions[$index]}"

    case "$action" in
      create)
        mkdir -p "$(dirname "$target")"
        cp "$source_file" "$target"
        created_count=$((created_count + 1))
        ;;
      overwrite)
        mkdir -p "$(dirname "$target")"
        cp "$source_file" "$target"
        updated_count=$((updated_count + 1))
        ;;
      unchanged)
        unchanged_count=$((unchanged_count + 1))
        ;;
      keep)
        kept_files+=("$target")
        ;;
    esac

    index=$((index + 1))
  done
}

create_mutable() {
  local target="$1"
  local initial_content="$2"

  if [ ! -e "$target" ]; then
    mkdir -p "$(dirname "$target")"
    printf '%s' "$initial_content" >"$target"
  fi
}

create_mutable_from_file() {
  local source_file="$1"
  local target="$2"

  if [ ! -e "$target" ]; then
    mkdir -p "$(dirname "$target")"
    cp "$source_file" "$target"
  fi
}

plan_managed "$SOURCE_ROOT/templates/workspace/AGENTS.md.tmpl" "$WORKSPACE_ROOT/AGENTS.md"
plan_managed "$SOURCE_ROOT/templates/workspace/CLAUDE.md.tmpl" "$WORKSPACE_ROOT/CLAUDE.md"
plan_managed "$SOURCE_ROOT/templates/workspace/IMPLEMENTER.md.tmpl" "$WORKSPACE_ROOT/IMPLEMENTER.md"
plan_managed "$SOURCE_ROOT/scripts/codex-review.sh" "$WORKSPACE_ROOT/scripts/codex-review.sh"
plan_managed "$SOURCE_ROOT/templates/workspace/agent-workflow.rules.tmpl" "$WORKSPACE_ROOT/.codex/rules/agent-workflow.rules"

for skill_dir in "$SOURCE_ROOT"/templates/skills/*; do
  [ -f "$skill_dir/SKILL.md" ] || continue
  skill_name="$(basename "$skill_dir")"
  plan_managed "$skill_dir/SKILL.md" "$WORKSPACE_ROOT/.claude/skills/$skill_name/SKILL.md"
  plan_managed "$skill_dir/SKILL.md" "$WORKSPACE_ROOT/.codex/skills/$skill_name/SKILL.md"
done

for repository in "${repositories[@]}"; do
  plan_managed "$SOURCE_ROOT/templates/repository/AGENTS.md.tmpl" "$repository/.agent/AGENTS.md"
done

apply_managed

chmod +x "$WORKSPACE_ROOT/scripts/codex-review.sh"
create_mutable_from_file "$SOURCE_ROOT/templates/workspace/TASK_PLAN.md.tmpl" "$WORKSPACE_ROOT/TASK_PLAN.md"
create_mutable "$WORKSPACE_ROOT/.agent/initial-request.md" "# Initial Request
"
create_mutable "$WORKSPACE_ROOT/.agent/review-history.md" "# Review History
"

for repository in "${repositories[@]}"; do
  create_mutable_from_file "$SOURCE_ROOT/templates/repository/current-slice.md.tmpl" "$repository/.agent/current-slice.md"
  create_mutable "$repository/.agent/review-attempts" "0
"

  exclude_path="$(git -C "$repository" rev-parse --git-path info/exclude)"
  case "$exclude_path" in
    /*) ;;
    *) exclude_path="$repository/$exclude_path" ;;
  esac
  mkdir -p "$(dirname "$exclude_path")"
  touch "$exclude_path"
  if ! grep -qxF '.agent/' "$exclude_path"; then
    if grep -qxF '# Local agent workflow' "$exclude_path"; then
      printf '.agent/\n' >>"$exclude_path"
    else
      printf '\n# Local agent workflow\n.agent/\n' >>"$exclude_path"
    fi
  fi
done

WORK_ITEM="$(basename "$WORKSPACE_ROOT")"
printf 'Workspace: %s\n' "$WORKSPACE_ROOT"
printf 'Work item: %s\n' "$WORK_ITEM"
printf 'Branch: %s\n' "$WORK_ITEM"
printf 'PR base: staging\n\n'
printf 'Repositories:\n'
for repository in "${repositories[@]}"; do
  printf '%s\n' "- $(basename "$repository")"
done
printf '\nManaged files: %s created, %s updated, %s unchanged, %s kept\n' \
  "$created_count" "$updated_count" "$unchanged_count" "${#kept_files[@]}"
if [ "${#kept_files[@]}" -gt 0 ]; then
  printf 'Kept your version of:\n'
  for kept in "${kept_files[@]}"; do
    printf '%s\n' "- ${kept#"$WORKSPACE_ROOT"/}"
  done
fi
printf '\nStart `claude` or `codex` from: %s\n' "$WORKSPACE_ROOT"
