#!/usr/bin/env bash
set -euo pipefail

echo "## Git status"
git status --short

echo
echo "## Changed files"
git diff --name-only

echo
echo "## Diff stat"
git diff --stat

echo
echo "## Latest Codex review"
if [ -f .agent/latest-codex-review.md ]; then
  cat .agent/latest-codex-review.md
else
  echo "No Codex review found."
fi
