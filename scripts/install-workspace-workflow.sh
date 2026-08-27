#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORKSPACE_ROOT="$(pwd -P)"

if [ "$#" -ne 0 ]; then
  echo "Usage: install-workspace-workflow.sh" >&2
  exit 1
fi

if git -C "$WORKSPACE_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Workspace root must be a plain directory, not a Git repository or a directory inside one: $WORKSPACE_ROOT" >&2
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

check_static() {
  local source_file="$1"
  local destination="$2"

  if [ -e "$destination" ] || [ -L "$destination" ]; then
    if [ ! -f "$destination" ] || ! cmp -s "$source_file" "$destination"; then
      echo "Conflicting static workflow file: $destination" >&2
      exit 1
    fi
  fi
}

# Complete every collision check before creating any file or directory.
check_static "$SOURCE_ROOT/templates/workspace/AGENTS.md.tmpl" "$WORKSPACE_ROOT/AGENTS.md"
check_static "$SOURCE_ROOT/templates/workspace/CLAUDE.md.tmpl" "$WORKSPACE_ROOT/CLAUDE.md"
check_static "$SOURCE_ROOT/templates/workspace/IMPLEMENTER.md.tmpl" "$WORKSPACE_ROOT/IMPLEMENTER.md"
check_static "$SOURCE_ROOT/scripts/codex-review.sh" "$WORKSPACE_ROOT/scripts/codex-review.sh"
check_static "$SOURCE_ROOT/templates/workspace/agent-workflow.rules.tmpl" "$WORKSPACE_ROOT/.codex/rules/agent-workflow.rules"

for repository in "${repositories[@]}"; do
  check_static "$SOURCE_ROOT/templates/repository/AGENTS.md.tmpl" "$repository/.agent/AGENTS.md"
done

install_static() {
  local source_file="$1"
  local destination="$2"

  if [ ! -e "$destination" ]; then
    cp "$source_file" "$destination"
  fi
}

create_mutable() {
  local destination="$1"
  local initial_content="$2"

  if [ ! -e "$destination" ]; then
    printf '%s' "$initial_content" >"$destination"
  fi
}

create_mutable_from_file() {
  local source_file="$1"
  local destination="$2"

  if [ ! -e "$destination" ]; then
    cp "$source_file" "$destination"
  fi
}

mkdir -p "$WORKSPACE_ROOT/scripts" "$WORKSPACE_ROOT/.codex/rules" "$WORKSPACE_ROOT/.agent"
install_static "$SOURCE_ROOT/templates/workspace/AGENTS.md.tmpl" "$WORKSPACE_ROOT/AGENTS.md"
install_static "$SOURCE_ROOT/templates/workspace/CLAUDE.md.tmpl" "$WORKSPACE_ROOT/CLAUDE.md"
install_static "$SOURCE_ROOT/templates/workspace/IMPLEMENTER.md.tmpl" "$WORKSPACE_ROOT/IMPLEMENTER.md"
install_static "$SOURCE_ROOT/scripts/codex-review.sh" "$WORKSPACE_ROOT/scripts/codex-review.sh"
install_static "$SOURCE_ROOT/templates/workspace/agent-workflow.rules.tmpl" "$WORKSPACE_ROOT/.codex/rules/agent-workflow.rules"
create_mutable_from_file "$SOURCE_ROOT/templates/workspace/TASK_PLAN.md.tmpl" "$WORKSPACE_ROOT/TASK_PLAN.md"
create_mutable "$WORKSPACE_ROOT/.agent/initial-request.md" "# Initial Request
"
create_mutable "$WORKSPACE_ROOT/.agent/review-history.md" "# Review History
"
chmod +x "$WORKSPACE_ROOT/scripts/codex-review.sh"

for repository in "${repositories[@]}"; do
  mkdir -p "$repository/.agent"
  install_static "$SOURCE_ROOT/templates/repository/AGENTS.md.tmpl" "$repository/.agent/AGENTS.md"
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
printf 'Expected branch: %s\n' "$WORK_ITEM"
printf 'PR base: staging\n\n'
printf 'Repositories:\n'
for repository in "${repositories[@]}"; do
  printf '%s\n' "- $(basename "$repository")"
done
printf '\nStart `claude` or `codex` from: %s\n' "$WORKSPACE_ROOT"
