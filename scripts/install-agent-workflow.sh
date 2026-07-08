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
copy_file "$TEMPLATE_ROOT/TASK_PLAN.md" "$TARGET_ROOT/TASK_PLAN.md"
copy_file "$TEMPLATE_ROOT/STARTUP_PROMPT.md" "$TARGET_ROOT/STARTUP_PROMPT.md"
copy_file "$TEMPLATE_ROOT/prompts/codex-review.md" "$TARGET_ROOT/prompts/codex-review.md"
copy_file "$TEMPLATE_ROOT/scripts/codex-review.sh" "$TARGET_ROOT/scripts/codex-review.sh"
copy_file "$TEMPLATE_ROOT/scripts/agent-status.sh" "$TARGET_ROOT/scripts/agent-status.sh"

chmod +x "$TARGET_ROOT/scripts/codex-review.sh"
chmod +x "$TARGET_ROOT/scripts/agent-status.sh"

touch "$TARGET_ROOT/.agent/initial-request.md"
touch "$TARGET_ROOT/.agent/review-history.md"

EXCLUDE_FILE="$TARGET_ROOT/.git/info/exclude"

if ! grep -q "Local Claude + Codex agent workflow" "$EXCLUDE_FILE"; then
  cat >> "$EXCLUDE_FILE" <<'EOF'

# Local Claude + Codex agent workflow
CLAUDE.md
AGENTS.md
TASK_PLAN.md
STARTUP_PROMPT.md
prompts/codex-review.md
scripts/codex-review.sh
scripts/agent-status.sh
.agent/
EOF

  echo "Added workflow files to .git/info/exclude"
else
  echo "Workflow ignore rules already exist in .git/info/exclude"
fi

echo
echo "Agent workflow installed."
echo
echo "Next:"
echo "1. Open Claude Code from this repo."
echo "2. Ask Claude: Read @STARTUP_PROMPT.md and follow it."
