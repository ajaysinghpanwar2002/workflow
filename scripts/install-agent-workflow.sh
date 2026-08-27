#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TARGET_ROOT="$(pwd -P)"

if [ "$#" -ne 0 ]; then
  echo "Usage: install-agent-workflow.sh" >&2
  exit 1
fi

git_root="$(git -C "$TARGET_ROOT" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Current directory is not a Git repository root: $TARGET_ROOT" >&2
  exit 1
}
resolved_git_root="$(cd "$git_root" && pwd -P)"
if [ "$resolved_git_root" != "$TARGET_ROOT" ]; then
  echo "Run this installer from the exact Git repository root: $resolved_git_root" >&2
  exit 1
fi

check_project_instruction() {
  local source_file="$1"
  local destination="$2"

  if [ -e "$destination" ] || [ -L "$destination" ]; then
    if [ ! -f "$destination" ] || ! cmp -s "$source_file" "$destination"; then
      echo "This repository already has project-owned agent instructions." >&2
      echo "Use install-workspace-workflow.sh from a parent workspace instead." >&2
      exit 1
    fi
  fi
}

check_static() {
  local source_file="$1"
  local destination="$2"

  if [ -e "$destination" ] || [ -L "$destination" ]; then
    if [ ! -f "$destination" ] || ! cmp -s "$source_file" "$destination"; then
      echo "Refusing to overwrite conflicting workflow file: $destination" >&2
      exit 1
    fi
  fi
}

# Complete every collision check before creating any file or directory.
check_project_instruction "$SOURCE_ROOT/templates/workspace/AGENTS.md.tmpl" "$TARGET_ROOT/AGENTS.md"
check_project_instruction "$SOURCE_ROOT/templates/workspace/CLAUDE.md.tmpl" "$TARGET_ROOT/CLAUDE.md"
check_static "$SOURCE_ROOT/templates/workspace/IMPLEMENTER.md.tmpl" "$TARGET_ROOT/IMPLEMENTER.md"
check_static "$SOURCE_ROOT/scripts/codex-review.sh" "$TARGET_ROOT/scripts/codex-review.sh"
check_static "$SOURCE_ROOT/templates/workspace/agent-workflow.rules.tmpl" "$TARGET_ROOT/.codex/rules/agent-workflow.rules"
check_static "$SOURCE_ROOT/templates/repository/AGENTS.md.tmpl" "$TARGET_ROOT/.agent/AGENTS.md"

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

mkdir -p "$TARGET_ROOT/scripts" "$TARGET_ROOT/.agent" "$TARGET_ROOT/.codex/rules"
install_static "$SOURCE_ROOT/templates/workspace/AGENTS.md.tmpl" "$TARGET_ROOT/AGENTS.md"
install_static "$SOURCE_ROOT/templates/workspace/CLAUDE.md.tmpl" "$TARGET_ROOT/CLAUDE.md"
install_static "$SOURCE_ROOT/templates/workspace/IMPLEMENTER.md.tmpl" "$TARGET_ROOT/IMPLEMENTER.md"
install_static "$SOURCE_ROOT/templates/repository/AGENTS.md.tmpl" "$TARGET_ROOT/.agent/AGENTS.md"
install_static "$SOURCE_ROOT/scripts/codex-review.sh" "$TARGET_ROOT/scripts/codex-review.sh"
install_static "$SOURCE_ROOT/templates/workspace/agent-workflow.rules.tmpl" "$TARGET_ROOT/.codex/rules/agent-workflow.rules"
create_mutable_from_file "$SOURCE_ROOT/templates/workspace/TASK_PLAN.md.tmpl" "$TARGET_ROOT/TASK_PLAN.md"
create_mutable_from_file "$SOURCE_ROOT/templates/repository/current-slice.md.tmpl" "$TARGET_ROOT/.agent/current-slice.md"
create_mutable "$TARGET_ROOT/.agent/initial-request.md" "# Initial Request
"
create_mutable "$TARGET_ROOT/.agent/review-history.md" "# Review History
"
create_mutable "$TARGET_ROOT/.agent/review-attempts" "0
"
chmod +x "$TARGET_ROOT/scripts/codex-review.sh"

exclude_path="$(git -C "$TARGET_ROOT" rev-parse --git-path info/exclude)"
case "$exclude_path" in
  /*) ;;
  *) exclude_path="$TARGET_ROOT/$exclude_path" ;;
esac
mkdir -p "$(dirname "$exclude_path")"
touch "$exclude_path"

add_exclude() {
  local pattern="$1"
  if ! grep -qxF "$pattern" "$exclude_path"; then
    printf '%s\n' "$pattern" >>"$exclude_path"
  fi
}

if ! grep -qxF '# Local agent workflow' "$exclude_path"; then
  printf '\n# Local agent workflow\n' >>"$exclude_path"
fi
add_exclude 'AGENTS.md'
add_exclude 'CLAUDE.md'
add_exclude 'IMPLEMENTER.md'
add_exclude 'TASK_PLAN.md'
add_exclude 'scripts/codex-review.sh'
add_exclude '.codex/'
add_exclude '.agent/'

printf 'Legacy direct-repository workflow installed in: %s\n' "$TARGET_ROOT"
printf 'Workspace mode is recommended, including for one repository.\n'
printf 'Start `claude` or `codex` from the repository root.\n'
