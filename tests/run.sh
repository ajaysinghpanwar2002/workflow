#!/usr/bin/env bash
set -uo pipefail

# The suite symlinks this file as `codex` to provide a dependency-free fake.
if [ "${WORKFLOW_FAKE_CODEX:-}" = "1" ]; then
  count_file="$FAKE_CODEX_RECORD_DIR/count"
  count=0
  if [ -f "$count_file" ]; then
    count="$(sed -n '1p' "$count_file")"
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$count_file"
  printf '%s\n' "$PWD" >"$FAKE_CODEX_RECORD_DIR/process-cwd"
  printf '%s\n' "$@" >"$FAKE_CODEX_RECORD_DIR/args"

  output_file=""
  review_cwd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --output-last-message)
        shift
        output_file="$1"
        ;;
      --cd)
        shift
        review_cwd="$1"
        ;;
    esac
    shift
  done

  printf '%s\n' "$review_cwd" >"$FAKE_CODEX_RECORD_DIR/review-cwd"
  if [ -n "$review_cwd" ]; then
    ls -A "$review_cwd" >"$FAKE_CODEX_RECORD_DIR/review-cwd-listing"
    git -C "$review_cwd" rev-parse --show-toplevel >"$FAKE_CODEX_RECORD_DIR/git-root"
    git -C "$review_cwd" status --porcelain >"$FAKE_CODEX_RECORD_DIR/git-status"
  fi
  if [ -n "$output_file" ]; then
    printf '%s' "${FAKE_CODEX_OUTPUT-No actionable findings.}" >"$output_file"
  fi
  exit "${FAKE_CODEX_EXIT:-0}"
fi

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INSTALLER="$SOURCE_ROOT/scripts/install.sh"

test_root_created="$(mktemp -d "${TMPDIR:-/tmp}/workflow-tests.XXXXXX")"
TEST_ROOT="$(cd "$test_root_created" && pwd -P)"
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

passed=0
failed=0

assert_file() {
  [ -f "$1" ] || {
    echo "Expected file: $1" >&2
    exit 1
  }
}

assert_not_exists() {
  [ ! -e "$1" ] || {
    echo "Expected path to be absent: $1" >&2
    exit 1
  }
}

assert_contains() {
  grep -Fq -- "$2" "$1" || {
    echo "Expected '$2' in $1" >&2
    exit 1
  }
}

assert_not_contains() {
  if grep -Fq -- "$2" "$1"; then
    echo "Did not expect '$2' in $1" >&2
    exit 1
  fi
}

assert_eq() {
  [ "$1" = "$2" ] || {
    echo "Expected '$1' to equal '$2'" >&2
    exit 1
  }
}

assert_same_file() {
  cmp -s "$1" "$2" || {
    echo "Expected identical files: $1 and $2" >&2
    exit 1
  }
}

init_repo() {
  local repository="$1"
  mkdir -p "$repository"
  git -C "$repository" init -q
  git -C "$repository" config user.email workflow-tests@example.com
  git -C "$repository" config user.name "Workflow Tests"
  printf 'base\n' >"$repository/base.txt"
  git -C "$repository" add base.txt
  git -C "$repository" commit -qm base
}

install_into() {
  local workspace="$1"
  shift
  (cd "$workspace" && "$INSTALLER" "$@") </dev/null
}

install_with_answers() {
  local workspace="$1"
  local answers="$2"
  printf '%s' "$answers" | (cd "$workspace" && "$INSTALLER")
}

new_workspace() {
  local workspace="$1"
  shift
  mkdir -p "$workspace"
  local repository
  for repository in "$@"; do
    init_repo "$workspace/$repository"
  done
}

exclude_file() {
  local repository="$1"
  local path
  path="$(git -C "$repository" rev-parse --git-path info/exclude)"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s\n' "$repository/$path" ;;
  esac
}

make_fake_path() {
  local directory="$1"
  mkdir -p "$directory/bin" "$directory/records"
  ln -s "$SOURCE_ROOT/tests/run.sh" "$directory/bin/codex"
  printf '%s\n' "$directory/bin"
}

make_reviewable() {
  local workspace="$1"
  local repository="$2"
  printf '# Slice\n\nGoal: Review change\n\nScope: %s\n\nOut: everything else\n\nTests: true\n\nContract:\n' \
    "$repository" >"$workspace/$repository/.agent/current-slice.md"
  printf 'change\n' >"$workspace/$repository/change.txt"
}

prepare_review_workspace() {
  local directory="$1"
  new_workspace "$directory/workspace" service-a service-b
  install_into "$directory/workspace" >/dev/null
  make_reviewable "$directory/workspace" service-a
}

run_fake_review() {
  local fake_root="$1"
  shift
  PATH="$fake_root/bin:$PATH" \
    CODEX_SANDBOX_NETWORK_DISABLED=0 \
    WORKFLOW_FAKE_CODEX=1 \
    FAKE_CODEX_RECORD_DIR="$fake_root/records" \
    FAKE_CODEX_OUTPUT="${TEST_CODEX_OUTPUT-No actionable findings.}" \
    FAKE_CODEX_EXIT="${TEST_CODEX_EXIT-0}" \
    "$@"
}

run_test() {
  local name="$1"
  shift
  (set -e; "$@")
  local status=$?
  if [ "$status" -eq 0 ]; then
    printf 'ok - %s\n' "$name"
    passed=$((passed + 1))
  else
    printf 'not ok - %s\n' "$name" >&2
    failed=$((failed + 1))
  fi
}

test_source_template_isolation() {
  assert_file "$SOURCE_ROOT/templates/workspace/AGENTS.md.tmpl"
  assert_file "$SOURCE_ROOT/templates/workspace/CLAUDE.md.tmpl"
  assert_file "$SOURCE_ROOT/templates/repository/AGENTS.md.tmpl"
  assert_file "$SOURCE_ROOT/templates/skills/unslop/SKILL.md"
  assert_not_exists "$SOURCE_ROOT/templates/workspace/AGENTS.md"
  assert_not_exists "$SOURCE_ROOT/templates/workspace/CLAUDE.md"
  assert_contains "$SOURCE_ROOT/AGENTS.md" '# Workflow Repository Development'
  assert_not_contains "$SOURCE_ROOT/AGENTS.md" '# Reviewer'
  assert_eq "$(cat "$SOURCE_ROOT/CLAUDE.md")" '@AGENTS.md'
  assert_contains "$SOURCE_ROOT/AGENTS.md" 'Do not install or execute the generated workflow'
  assert_not_exists "$SOURCE_ROOT/.codex/rules/agent-workflow.rules"
  assert_not_exists "$SOURCE_ROOT/IMPLEMENTER.md"
  assert_not_exists "$SOURCE_ROOT/TASK_PLAN.md"
  # Skills must not be discoverable inside this source repository.
  assert_not_exists "$SOURCE_ROOT/.claude/skills"
  assert_not_exists "$SOURCE_ROOT/.codex/skills"
  assert_not_exists "$SOURCE_ROOT/.agents/skills"
}

test_single_installer_is_the_only_installer() {
  assert_file "$INSTALLER"
  assert_not_exists "$SOURCE_ROOT/scripts/install-agent-workflow.sh"
  assert_not_exists "$SOURCE_ROOT/scripts/install-workspace-workflow.sh"
  assert_not_contains "$SOURCE_ROOT/README.md" 'install-agent-workflow.sh'
  assert_not_contains "$SOURCE_ROOT/templates/workspace/IMPLEMENTER.md.tmpl" 'Direct-repository'
}

test_one_and_two_repositories() {
  local directory="$TEST_ROOT/repository-counts"
  new_workspace "$directory/one" service-a
  new_workspace "$directory/two" service-a service-b
  mkdir -p "$directory/two/not-a-repository"
  install_into "$directory/one" >"$directory/one-output"
  install_into "$directory/two" >"$directory/two-output"
  assert_file "$directory/one/AGENTS.md"
  assert_file "$directory/one/service-a/.agent/AGENTS.md"
  assert_file "$directory/two/service-a/.agent/AGENTS.md"
  assert_file "$directory/two/service-b/.agent/AGENTS.md"
  assert_not_exists "$directory/two/not-a-repository/.agent"
  assert_contains "$directory/two-output" '- service-a'
  assert_contains "$directory/two-output" '- service-b'
  assert_eq "$(cat "$directory/one/CLAUDE.md")" '@AGENTS.md'
}

test_rejects_invalid_roots() {
  local directory="$TEST_ROOT/invalid-roots"
  mkdir -p "$directory/empty"
  if install_into "$directory/empty" >"$directory/empty.log" 2>&1; then return 1; fi
  assert_not_exists "$directory/empty/AGENTS.md"

  mkdir -p "$directory/git-workspace"
  init_repo "$directory/git-workspace"
  init_repo "$directory/git-workspace/service-a"
  if install_into "$directory/git-workspace" >"$directory/git.log" 2>&1; then return 1; fi

  init_repo "$directory/parent"
  mkdir -p "$directory/parent/work-item"
  init_repo "$directory/parent/work-item/service-a"
  if install_into "$directory/parent/work-item" >"$directory/parent.log" 2>&1; then return 1; fi
  assert_not_exists "$directory/parent/work-item/AGENTS.md"

  new_workspace "$directory/bad-argument" service-a
  if install_into "$directory/bad-argument" --nope >"$directory/argument.log" 2>&1; then return 1; fi
  assert_not_exists "$directory/bad-argument/AGENTS.md"
}

test_worktrees_and_spaces() {
  local directory="$TEST_ROOT/worktrees and spaces"
  mkdir -p "$directory/workspace with spaces"
  init_repo "$directory/source repository"
  git -C "$directory/source repository" worktree add -q -b ticket "$directory/workspace with spaces/service worktree"
  install_into "$directory/workspace with spaces" >/dev/null
  assert_file "$directory/workspace with spaces/service worktree/.agent/AGENTS.md"
  assert_contains "$(exclude_file "$directory/workspace with spaces/service worktree")" '.agent/'
}

test_installs_skills_for_both_agents() {
  local directory="$TEST_ROOT/skills"
  new_workspace "$directory/workspace" service-a
  install_into "$directory/workspace" >/dev/null
  local template="$SOURCE_ROOT/templates/skills/unslop/SKILL.md"
  assert_same_file "$template" "$directory/workspace/.claude/skills/unslop/SKILL.md"
  assert_same_file "$template" "$directory/workspace/.codex/skills/unslop/SKILL.md"
  assert_contains "$directory/workspace/.claude/skills/unslop/SKILL.md" 'name: unslop'
  # Skills belong to the workspace, not to the reviewed repositories.
  assert_not_exists "$directory/workspace/service-a/.claude"
  assert_not_exists "$directory/workspace/service-a/.codex"
}

test_idempotent_and_preserves_task_state() {
  local directory="$TEST_ROOT/idempotent"
  new_workspace "$directory/workspace" service-a
  install_into "$directory/workspace" >/dev/null
  printf 'custom plan\n' >"$directory/workspace/TASK_PLAN.md"
  printf 'custom request\n' >"$directory/workspace/.agent/initial-request.md"
  printf 'custom history\n' >"$directory/workspace/.agent/review-history.md"
  printf 'custom slice\n' >"$directory/workspace/service-a/.agent/current-slice.md"
  printf '1\n' >"$directory/workspace/.agent/reviews/service-a/review-attempts"
  install_into "$directory/workspace" >"$directory/second.log"
  assert_eq "$(sed -n '1p' "$directory/workspace/TASK_PLAN.md")" 'custom plan'
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/initial-request.md")" 'custom request'
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/review-history.md")" 'custom history'
  assert_eq "$(sed -n '1p' "$directory/workspace/service-a/.agent/current-slice.md")" 'custom slice'
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-a/review-attempts")" '1'
  assert_eq "$(grep -xcF '.agent/' "$(exclude_file "$directory/workspace/service-a")")" '1'
  assert_contains "$directory/second.log" '0 created, 0 updated'
}

test_update_keeps_changed_files_without_an_answer() {
  local directory="$TEST_ROOT/update-default"
  new_workspace "$directory/workspace" service-a
  install_into "$directory/workspace" >/dev/null
  printf 'local edit\n' >"$directory/workspace/IMPLEMENTER.md"
  install_into "$directory/workspace" >"$directory/output" 2>&1 || return 1
  assert_eq "$(cat "$directory/workspace/IMPLEMENTER.md")" 'local edit'
  assert_contains "$directory/output" 'differs from the workflow version.'
  assert_contains "$directory/output" '1 kept'
  assert_contains "$directory/output" '- IMPLEMENTER.md'
}

test_update_shows_diff_then_overwrites_one_file() {
  local directory="$TEST_ROOT/update-diff"
  new_workspace "$directory/workspace" service-a
  install_into "$directory/workspace" >/dev/null
  printf 'local edit\n' >"$directory/workspace/AGENTS.md"
  printf 'local edit\n' >"$directory/workspace/IMPLEMENTER.md"
  install_with_answers "$directory/workspace" 'd
o
' >"$directory/output" 2>&1 || return 1
  assert_contains "$directory/output" '-local edit'
  assert_same_file "$SOURCE_ROOT/templates/workspace/AGENTS.md.tmpl" "$directory/workspace/AGENTS.md"
  # The prompt is per file, so the second conflict falls back to the keep default.
  assert_eq "$(cat "$directory/workspace/IMPLEMENTER.md")" 'local edit'
  assert_contains "$directory/output" '1 updated'
}

test_update_answers_apply_to_all_remaining_files() {
  local directory="$TEST_ROOT/update-all"
  new_workspace "$directory/overwrite" service-a
  install_into "$directory/overwrite" >/dev/null
  printf 'local edit\n' >"$directory/overwrite/AGENTS.md"
  printf 'local edit\n' >"$directory/overwrite/IMPLEMENTER.md"
  printf 'local edit\n' >"$directory/overwrite/service-a/.agent/AGENTS.md"
  install_with_answers "$directory/overwrite" 'a
' >"$directory/overwrite.log" 2>&1 || return 1
  assert_same_file "$SOURCE_ROOT/templates/workspace/AGENTS.md.tmpl" "$directory/overwrite/AGENTS.md"
  assert_same_file "$SOURCE_ROOT/templates/workspace/IMPLEMENTER.md.tmpl" "$directory/overwrite/IMPLEMENTER.md"
  assert_same_file "$SOURCE_ROOT/templates/repository/AGENTS.md.tmpl" "$directory/overwrite/service-a/.agent/AGENTS.md"
  assert_contains "$directory/overwrite.log" '3 updated'

  new_workspace "$directory/keep" service-a
  install_into "$directory/keep" >/dev/null
  printf 'local edit\n' >"$directory/keep/AGENTS.md"
  printf 'local edit\n' >"$directory/keep/IMPLEMENTER.md"
  install_with_answers "$directory/keep" 's
' >"$directory/keep.log" 2>&1 || return 1
  assert_eq "$(cat "$directory/keep/AGENTS.md")" 'local edit'
  assert_eq "$(cat "$directory/keep/IMPLEMENTER.md")" 'local edit'
  assert_contains "$directory/keep.log" '2 kept'
}

test_update_flags_skip_the_prompt() {
  local directory="$TEST_ROOT/update-flags"
  new_workspace "$directory/workspace" service-a
  install_into "$directory/workspace" >/dev/null
  printf 'local edit\n' >"$directory/workspace/AGENTS.md"
  install_into "$directory/workspace" --keep-all >"$directory/keep.log" 2>&1
  assert_eq "$(cat "$directory/workspace/AGENTS.md")" 'local edit'
  assert_not_contains "$directory/keep.log" 'differs from the workflow version.'
  install_into "$directory/workspace" --overwrite-all >"$directory/overwrite.log" 2>&1
  assert_same_file "$SOURCE_ROOT/templates/workspace/AGENTS.md.tmpl" "$directory/workspace/AGENTS.md"
  assert_not_contains "$directory/overwrite.log" 'differs from the workflow version.'
}

test_update_abort_writes_nothing() {
  local directory="$TEST_ROOT/update-abort"
  new_workspace "$directory/workspace" service-a
  install_into "$directory/workspace" >/dev/null
  printf 'local edit\n' >"$directory/workspace/AGENTS.md"
  printf 'local edit\n' >"$directory/workspace/IMPLEMENTER.md"
  rm "$directory/workspace/TASK_PLAN.md"
  if install_with_answers "$directory/workspace" 'q
' >"$directory/output" 2>&1; then return 1; fi
  assert_contains "$directory/output" 'Aborted. Nothing was written.'
  assert_eq "$(cat "$directory/workspace/AGENTS.md")" 'local edit'
  assert_eq "$(cat "$directory/workspace/IMPLEMENTER.md")" 'local edit'
  assert_not_exists "$directory/workspace/TASK_PLAN.md"
}

test_refuses_non_regular_managed_paths() {
  local directory="$TEST_ROOT/non-regular"
  new_workspace "$directory/workspace" service-a
  mkdir -p "$directory/workspace/service-a/.agent/AGENTS.md"
  if install_into "$directory/workspace" >"$directory/output" 2>&1; then return 1; fi
  assert_contains "$directory/output" 'Refusing to replace a symlink or non-regular file'
  assert_not_exists "$directory/workspace/AGENTS.md"
  assert_not_exists "$directory/workspace/TASK_PLAN.md"
}

test_preserves_project_instructions_and_excludes() {
  local directory="$TEST_ROOT/project-files"
  new_workspace "$directory/workspace" service-a service-b
  printf 'project agents\n' >"$directory/workspace/service-a/AGENTS.md"
  printf 'project claude\n' >"$directory/workspace/service-a/CLAUDE.md"
  cp "$directory/workspace/service-a/AGENTS.md" "$directory/agents.before"
  cp "$directory/workspace/service-a/CLAUDE.md" "$directory/claude.before"
  install_into "$directory/workspace" >/dev/null
  assert_same_file "$directory/agents.before" "$directory/workspace/service-a/AGENTS.md"
  assert_same_file "$directory/claude.before" "$directory/workspace/service-a/CLAUDE.md"
  assert_not_exists "$directory/workspace/service-b/AGENTS.md"
  assert_not_exists "$directory/workspace/service-b/CLAUDE.md"
  assert_file "$directory/workspace/service-a/.agent/AGENTS.md"
  local excludes
  excludes="$(exclude_file "$directory/workspace/service-a")"
  assert_contains "$excludes" '.agent/'
  assert_not_contains "$excludes" 'AGENTS.md'
  assert_not_contains "$excludes" 'CLAUDE.md'
}

test_skips_source_repository_child() {
  local directory="$TEST_ROOT/source-child"
  local workspace="$directory/workspace"
  mkdir -p "$workspace/workflow-source"
  cp -R "$SOURCE_ROOT/templates" "$workspace/workflow-source/templates"
  cp -R "$SOURCE_ROOT/scripts" "$workspace/workflow-source/scripts"
  init_repo "$workspace/workflow-source"
  git -C "$workspace/workflow-source" add templates scripts
  git -C "$workspace/workflow-source" commit -qm source
  init_repo "$workspace/service-a"
  (cd "$workspace" && "$workspace/workflow-source/scripts/install.sh") </dev/null >/dev/null
  assert_not_exists "$workspace/workflow-source/.agent"
  assert_file "$workspace/service-a/.agent/AGENTS.md"
}

test_review_argument_validation() {
  local directory="$TEST_ROOT/review-arguments"
  prepare_review_workspace "$directory"
  local script="$directory/workspace/scripts/codex-review.sh"
  if "$script" >"$directory/no-arg.log" 2>&1; then return 1; fi
  assert_contains "$directory/no-arg.log" 'Usage: codex-review.sh <repository>'
  if "$script" 'service-a/nested' >"$directory/nested.log" 2>&1; then return 1; fi
  if "$script" '..' >"$directory/dotdot.log" 2>&1; then return 1; fi
  if "$script" '/tmp' >"$directory/outside.log" 2>&1; then return 1; fi
  mkdir -p "$directory/workspace/not-git"
  if "$script" not-git >"$directory/not-git.log" 2>&1; then return 1; fi
  if "$script" service-a service-a >"$directory/duplicate.log" 2>&1; then return 1; fi
  assert_contains "$directory/duplicate.log" 'Repository listed more than once: service-a'
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-a/review-attempts")" '0'
}

test_review_validates_every_repository_before_starting() {
  local directory="$TEST_ROOT/review-preflight"
  prepare_review_workspace "$directory"
  make_fake_path "$directory/fake" >/dev/null
  local script="$directory/workspace/scripts/codex-review.sh"

  # service-b is named but has no changes, so nothing runs for service-a either.
  if run_fake_review "$directory/fake" "$script" service-a service-b >"$directory/clean.log" 2>&1; then return 1; fi
  assert_contains "$directory/clean.log" 'No staged, unstaged, or untracked changes found in service-b'
  assert_not_exists "$directory/fake/records/count"
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-a/review-attempts")" '0'

  # service-b is changed but its slice is still the empty template.
  printf 'change\n' >"$directory/workspace/service-b/change.txt"
  if run_fake_review "$directory/fake" "$script" service-a service-b >"$directory/slice.log" 2>&1; then return 1; fi
  assert_contains "$directory/slice.log" 'Current slice for service-b contains only empty template headings'
  assert_not_exists "$directory/fake/records/count"
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-a/review-attempts")" '0'

  # service-b already used both of its attempts.
  make_reviewable "$directory/workspace" service-b
  printf '2\n' >"$directory/workspace/.agent/reviews/service-b/review-attempts"
  if run_fake_review "$directory/fake" "$script" service-a service-b >"$directory/limit.log" 2>&1; then return 1; fi
  assert_contains "$directory/limit.log" 'Review limit reached for this slice: 2/2 in service-b.'
  assert_not_exists "$directory/fake/records/count"
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-a/review-attempts")" '0'
}

test_review_covers_every_named_repository() {
  local directory="$TEST_ROOT/review-many"
  prepare_review_workspace "$directory"
  make_reviewable "$directory/workspace" service-b
  make_fake_path "$directory/fake" >/dev/null
  run_fake_review "$directory/fake" "$directory/workspace/scripts/codex-review.sh" \
    service-a service-b >"$directory/output" 2>&1
  assert_eq "$(sed -n '1p' "$directory/fake/records/count")" '2'
  assert_file "$directory/workspace/service-a/.agent/latest-codex-review.md"
  assert_file "$directory/workspace/service-b/.agent/latest-codex-review.md"
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-a/review-attempts")" '1'
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-b/review-attempts")" '1'
  assert_contains "$directory/output" '- service-a: review written, attempt 1/2'
  assert_contains "$directory/output" '- service-b: review written, attempt 1/2'
}

test_review_stops_at_the_first_failure() {
  local directory="$TEST_ROOT/review-stop"
  prepare_review_workspace "$directory"
  make_reviewable "$directory/workspace" service-b
  make_fake_path "$directory/fake" >/dev/null
  TEST_CODEX_EXIT=7
  if run_fake_review "$directory/fake" "$directory/workspace/scripts/codex-review.sh" \
    service-a service-b >"$directory/output" 2>&1; then return 1; fi
  unset TEST_CODEX_EXIT
  assert_eq "$(sed -n '1p' "$directory/fake/records/count")" '1'
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-a/review-attempts")" '1'
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-b/review-attempts")" '0'
  assert_not_exists "$directory/workspace/service-b/.agent/latest-codex-review.md"
  assert_contains "$directory/output" '- service-a: reviewer failed, attempt 1/2 consumed'
  assert_contains "$directory/output" '- service-b: not reviewed, attempts untouched'
}

test_review_keeps_harness_state_out_of_the_reviewer_directory() {
  local directory="$TEST_ROOT/review-state"
  prepare_review_workspace "$directory"
  make_fake_path "$directory/fake" >/dev/null

  # A workspace from the layout that kept the harness in the reviewer's directory.
  rm -f "$directory/workspace/.agent/reviews/service-a/review-attempts"
  printf '1\n' >"$directory/workspace/service-a/.agent/review-attempts"
  printf 'stale log\n' >"$directory/workspace/service-a/.agent/latest-codex-review-run.log"
  printf 'stale pending\n' >"$directory/workspace/service-a/.agent/pending-codex-review.md"

  run_fake_review "$directory/fake" "$directory/workspace/scripts/codex-review.sh" \
    service-a >"$directory/output" 2>&1

  # The counter carried over, so this was attempt 2, not a fresh attempt 1.
  assert_contains "$directory/output" 'service-a: Codex review attempt 2/2'
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-a/review-attempts")" '2'
  assert_file "$directory/workspace/.agent/reviews/service-a/latest-codex-review-run.log"
  assert_not_exists "$directory/workspace/service-a/.agent/review-attempts"
  assert_not_exists "$directory/workspace/service-a/.agent/latest-codex-review-run.log"
  assert_not_exists "$directory/workspace/service-a/.agent/pending-codex-review.md"

  # The reviewer saw only the files it is told to read.
  local listing="$directory/fake/records/review-cwd-listing"
  assert_contains "$listing" 'current-slice.md'
  assert_contains "$listing" 'AGENTS.md'
  assert_not_contains "$listing" 'review-attempts'
  assert_not_contains "$listing" 'latest-codex-review-run.log'
  assert_not_contains "$listing" 'pending-codex-review.md'
}

test_install_migrates_a_counter_left_in_the_reviewer_directory() {
  local directory="$TEST_ROOT/migrate-install"
  new_workspace "$directory/workspace" service-a
  install_into "$directory/workspace" >/dev/null
  rm -f "$directory/workspace/.agent/reviews/service-a/review-attempts"
  printf '1\n' >"$directory/workspace/service-a/.agent/review-attempts"
  printf 'stale log\n' >"$directory/workspace/service-a/.agent/latest-codex-review-run.log"
  install_into "$directory/workspace" >/dev/null
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-a/review-attempts")" '1'
  assert_not_exists "$directory/workspace/service-a/.agent/review-attempts"
  assert_not_exists "$directory/workspace/service-a/.agent/latest-codex-review-run.log"
}

test_review_rejects_a_git_workspace() {
  local directory="$TEST_ROOT/review-git-workspace"
  prepare_review_workspace "$directory"
  git -C "$directory/workspace" init -q
  if "$directory/workspace/scripts/codex-review.sh" service-a >"$directory/output" 2>&1; then return 1; fi
  assert_contains "$directory/output" 'The workspace root must not be a Git repository or inside one'
}

test_review_targets_only_the_selected_repository() {
  local directory="$TEST_ROOT/review-target"
  prepare_review_workspace "$directory"
  printf 'sibling change\n' >"$directory/workspace/service-b/sibling.txt"
  make_fake_path "$directory/fake" >/dev/null
  run_fake_review "$directory/fake" "$directory/workspace/scripts/codex-review.sh" service-a >/dev/null
  assert_eq "$(sed -n '1p' "$directory/fake/records/review-cwd")" "$directory/workspace/service-a/.agent"
  assert_eq "$(sed -n '1p' "$directory/fake/records/git-root")" "$directory/workspace/service-a"
  assert_contains "$directory/fake/records/args" 'review'
  assert_contains "$directory/fake/records/args" '--uncommitted'
  assert_contains "$directory/fake/records/git-status" 'change.txt'
  assert_not_contains "$directory/fake/records/git-status" 'sibling.txt'
  assert_file "$directory/workspace/service-a/.agent/latest-codex-review.md"
  assert_not_exists "$directory/workspace/service-b/.agent/latest-codex-review.md"
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-b/review-attempts")" '0'
}

test_review_attempt_limit() {
  local directory="$TEST_ROOT/review-limit"
  prepare_review_workspace "$directory"
  rm "$directory/workspace/.agent/reviews/service-a/review-attempts"
  make_fake_path "$directory/fake" >/dev/null
  local script="$directory/workspace/scripts/codex-review.sh"
  run_fake_review "$directory/fake" "$script" service-a >/dev/null
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-a/review-attempts")" '1'
  run_fake_review "$directory/fake" "$script" service-a >/dev/null
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-a/review-attempts")" '2'
  if run_fake_review "$directory/fake" "$script" service-a >"$directory/third.log" 2>&1; then return 1; fi
  assert_eq "$(sed -n '1p' "$directory/fake/records/count")" '2'
  assert_contains "$directory/third.log" 'Review limit reached for this slice: 2/2 in service-a.'
  assert_contains "$directory/third.log" 'Mark the task Blocked and ask the user to intervene.'
}

test_review_validation_does_not_increment() {
  local directory="$TEST_ROOT/review-validation"
  prepare_review_workspace "$directory"
  cp "$SOURCE_ROOT/templates/repository/current-slice.md.tmpl" "$directory/workspace/service-a/.agent/current-slice.md"
  make_fake_path "$directory/fake" >/dev/null
  if run_fake_review "$directory/fake" "$directory/workspace/scripts/codex-review.sh" service-a >"$directory/output" 2>&1; then return 1; fi
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-a/review-attempts")" '0'
  assert_not_exists "$directory/fake/records/count"

  printf '# Slice\nGoal: valid\n' >"$directory/workspace/service-a/.agent/current-slice.md"
  printf 'invalid\n' >"$directory/workspace/.agent/reviews/service-a/review-attempts"
  if run_fake_review "$directory/fake" "$directory/workspace/scripts/codex-review.sh" service-a >"$directory/invalid" 2>&1; then return 1; fi
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/reviews/service-a/review-attempts")" 'invalid'
  assert_not_exists "$directory/fake/records/count"
}

test_failed_and_empty_reviews_consume_attempts() {
  local directory="$TEST_ROOT/review-failures"
  prepare_review_workspace "$directory/nonzero"
  make_fake_path "$directory/nonzero/fake" >/dev/null
  TEST_CODEX_EXIT=7
  if run_fake_review "$directory/nonzero/fake" "$directory/nonzero/workspace/scripts/codex-review.sh" service-a >"$directory/nonzero/output" 2>&1; then return 1; fi
  unset TEST_CODEX_EXIT
  assert_eq "$(sed -n '1p' "$directory/nonzero/workspace/.agent/reviews/service-a/review-attempts")" '1'
  assert_not_exists "$directory/nonzero/workspace/service-a/.agent/latest-codex-review.md"
  assert_file "$directory/nonzero/workspace/.agent/reviews/service-a/latest-codex-review-run.log"

  prepare_review_workspace "$directory/empty"
  printf 'stale clean review\n' >"$directory/empty/workspace/service-a/.agent/latest-codex-review.md"
  make_fake_path "$directory/empty/fake" >/dev/null
  TEST_CODEX_OUTPUT=''
  if run_fake_review "$directory/empty/fake" "$directory/empty/workspace/scripts/codex-review.sh" service-a >"$directory/empty/output" 2>&1; then return 1; fi
  unset TEST_CODEX_OUTPUT
  assert_eq "$(sed -n '1p' "$directory/empty/workspace/.agent/reviews/service-a/review-attempts")" '1'
  assert_not_exists "$directory/empty/workspace/service-a/.agent/latest-codex-review.md"
  assert_eq "$(sed -n '1p' "$directory/empty/workspace/service-a/.agent/previous-codex-review.md")" 'stale clean review'
}

test_review_artifact_rotation_and_success() {
  local directory="$TEST_ROOT/review-artifacts"
  prepare_review_workspace "$directory"
  printf 'old clean review\n' >"$directory/workspace/service-a/.agent/latest-codex-review.md"
  printf 'stale pending\n' >"$directory/workspace/.agent/reviews/service-a/pending-codex-review.md"
  make_fake_path "$directory/fake" >/dev/null
  TEST_CODEX_OUTPUT='new review'
  run_fake_review "$directory/fake" "$directory/workspace/scripts/codex-review.sh" service-a >/dev/null
  unset TEST_CODEX_OUTPUT
  assert_eq "$(sed -n '1p' "$directory/workspace/service-a/.agent/previous-codex-review.md")" 'old clean review'
  assert_eq "$(sed -n '1p' "$directory/workspace/service-a/.agent/latest-codex-review.md")" 'new review'
  assert_not_exists "$directory/workspace/.agent/reviews/service-a/pending-codex-review.md"
}

test_templates_capture_required_policy() {
  local entry="$SOURCE_ROOT/templates/workspace/AGENTS.md.tmpl"
  local reviewer="$SOURCE_ROOT/templates/repository/AGENTS.md.tmpl"
  local implementer="$SOURCE_ROOT/templates/workspace/IMPLEMENTER.md.tmpl"
  assert_eq "$(cat "$SOURCE_ROOT/templates/workspace/CLAUDE.md.tmpl")" '@AGENTS.md'
  assert_contains "$entry" 'root `AGENTS.md` and `CLAUDE.md`'
  assert_contains "$entry" "Never follow a repository's \`.agent/AGENTS.md\`"
  assert_contains "$entry" 'unslop'
  assert_contains "$reviewer" '- edit files'
  assert_contains "$reviewer" '- run mutating commands'
  assert_contains "$reviewer" 'read the workspace root'
  assert_contains "$reviewer" 'Read nothing else above the repository.'
  assert_contains "$implementer" '.agent/reviews/<repository>/'
  assert_contains "$implementer" 'Read a review run log only after a review failed'
  assert_contains "$implementer" 'Files survive a compaction. Context does not.'
  assert_contains "$implementer" 'Two review attempts per repository per slice. Never a third.'
  assert_contains "$implementer" 'unslop'
  assert_not_contains "$implementer" 'Caveman'
  assert_not_contains "$implementer" 'Ponytail'
  assert_contains "$implementer" 'WORK_ITEM="$(basename "$(pwd -P)")"'
  assert_contains "$implementer" '--base staging'
  assert_contains "$implementer" '--title "$WORK_ITEM"'
  assert_contains "$implementer" 'promotion PRs from `staging` to `release`'
  assert_contains "$implementer" 'without explicit user approval'
  assert_contains "$implementer" 'The slice is clean only when every changed repository has a clean latest review.'
  assert_contains "$implementer" 'scripts/codex-review.sh service-a service-b'
  assert_contains "$implementer" 'Do not load it while editing code.'
  assert_contains "$SOURCE_ROOT/templates/skills/unslop/SKILL.md" 'Skip it while editing code.'
}

run_test 'source templates stay inert in this repository' test_source_template_isolation
run_test 'only one installer remains' test_single_installer_is_the_only_installer
run_test 'installer handles one and two repositories' test_one_and_two_repositories
run_test 'installer rejects invalid roots and arguments' test_rejects_invalid_roots
run_test 'installer supports worktrees and spaces' test_worktrees_and_spaces
run_test 'installer installs skills for Claude and Codex' test_installs_skills_for_both_agents
run_test 'reinstall is idempotent and preserves task state' test_idempotent_and_preserves_task_state
run_test 'update keeps changed files when no answer is given' test_update_keeps_changed_files_without_an_answer
run_test 'update shows a diff then overwrites one file' test_update_shows_diff_then_overwrites_one_file
run_test 'update answers can apply to all remaining files' test_update_answers_apply_to_all_remaining_files
run_test 'update flags skip the prompt' test_update_flags_skip_the_prompt
run_test 'update abort writes nothing' test_update_abort_writes_nothing
run_test 'installer refuses non-regular managed paths' test_refuses_non_regular_managed_paths
run_test 'installer preserves project instructions and excludes only .agent' test_preserves_project_instructions_and_excludes
run_test 'installer skips its own source repository child' test_skips_source_repository_child
run_test 'review validates its repository arguments' test_review_argument_validation
run_test 'review validates every repository before starting' test_review_validates_every_repository_before_starting
run_test 'review covers every named repository' test_review_covers_every_named_repository
run_test 'review stops at the first failing repository' test_review_stops_at_the_first_failure
run_test 'review keeps harness state out of the reviewer directory' test_review_keeps_harness_state_out_of_the_reviewer_directory
run_test 'install migrates a counter left in the reviewer directory' test_install_migrates_a_counter_left_in_the_reviewer_directory
run_test 'review rejects a Git workspace root' test_review_rejects_a_git_workspace
run_test 'review targets only the selected repository' test_review_targets_only_the_selected_repository
run_test 'review attempts stop after two launches' test_review_attempt_limit
run_test 'review validation failures do not consume attempts' test_review_validation_does_not_increment
run_test 'failed and empty reviews consume attempts without approval' test_failed_and_empty_reviews_consume_attempts
run_test 'successful reviews rotate and replace artifacts' test_review_artifact_rotation_and_success
run_test 'templates capture branch, PR, review, skill, and role policy' test_templates_capture_required_policy

printf '\n%s passed; %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
