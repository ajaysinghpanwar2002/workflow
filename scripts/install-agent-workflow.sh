#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_ROOT="$(pwd)"

if [ ! -d "$TARGET_ROOT/.git" ]; then
  echo "This does not look like a git repo root: $TARGET_ROOT" >&2
  exit 1
fi

mkdir -p "$TARGET_ROOT/prompts"
mkdir -p "$TARGET_ROOT/scripts"
mkdir -p "$TARGET_ROOT/.agent"
mkdir -p "$TARGET_ROOT/.codex/rules"

copy_file() {
  local src="$1"
  local dest="$2"

  if [ -f "$dest" ]; then
    echo "Skipping existing file: $dest"
  else
    cp "$src" "$dest"
    echo "Copied: $dest"
  fi
}

copy_file "$TEMPLATE_ROOT/CLAUDE.md" "$TARGET_ROOT/CLAUDE.md"
copy_file "$TEMPLATE_ROOT/AGENTS.md" "$TARGET_ROOT/AGENTS.md"
copy_file "$TEMPLATE_ROOT/IMPLEMENTER.md" "$TARGET_ROOT/IMPLEMENTER.md"
copy_file "$TEMPLATE_ROOT/TASK_PLAN.md" "$TARGET_ROOT/TASK_PLAN.md"
copy_file "$TEMPLATE_ROOT/prompts/codex-review.md" "$TARGET_ROOT/prompts/codex-review.md"
copy_file "$TEMPLATE_ROOT/scripts/codex-review.sh" "$TARGET_ROOT/scripts/codex-review.sh"
copy_file "$TEMPLATE_ROOT/scripts/agent-status.sh" "$TARGET_ROOT/scripts/agent-status.sh"
copy_file "$TEMPLATE_ROOT/prompts/pre-compact.md" "$TARGET_ROOT/prompts/pre-compact.md"
copy_file "$TEMPLATE_ROOT/.codex/rules/agent-workflow.rules" "$TARGET_ROOT/.codex/rules/agent-workflow.rules"

chmod +x "$TARGET_ROOT/scripts/codex-review.sh"
chmod +x "$TARGET_ROOT/scripts/agent-status.sh"

touch "$TARGET_ROOT/.agent/initial-request.md"
touch "$TARGET_ROOT/.agent/review-history.md"
touch "$TARGET_ROOT/.agent/current-slice.md"

EXCLUDE_FILE="$TARGET_ROOT/.git/info/exclude"
EXCLUDE_MARKER="# Local implementer + Codex reviewer workflow"

if ! grep -qxF "$EXCLUDE_MARKER" "$EXCLUDE_FILE"; then
  printf '\n%s\n' "$EXCLUDE_MARKER" >> "$EXCLUDE_FILE"
fi

add_exclude() {
  local pattern="$1"

  if ! grep -qxF "$pattern" "$EXCLUDE_FILE"; then
    printf '%s\n' "$pattern" >> "$EXCLUDE_FILE"
  fi
}

add_exclude "CLAUDE.md"
add_exclude "AGENTS.md"
add_exclude "IMPLEMENTER.md"
add_exclude "TASK_PLAN.md"
add_exclude "prompts/codex-review.md"
add_exclude "scripts/codex-review.sh"
add_exclude "scripts/agent-status.sh"
add_exclude "prompts/pre-compact.md"
add_exclude ".codex/rules/agent-workflow.rules"
add_exclude ".agent/"

echo "Ensured workflow files are listed in .git/info/exclude"

echo
echo "Agent workflow installed."
echo
echo "Next:"
echo "1. Open Claude Code or Codex from this repo."
echo "2. In Claude Code, ask: Read @CLAUDE.md and follow it."
echo "3. In Codex CLI, ask: Read @AGENTS.md and follow it."
echo
echo "Codex as the implementer: .codex/rules/agent-workflow.rules pre-authorizes"
echo "scripts/codex-review.sh to run outside the Codex sandbox (the nested reviewer"
echo "needs network access). Project rules load only once you trust this repo's"
echo ".codex/ layer in Codex; until then, approve the escalation prompt when the"
echo "script runs. Keep the rule project-scoped; do not copy it into ~/.codex/rules/."
