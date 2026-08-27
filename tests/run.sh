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
    git -C "$review_cwd" rev-parse --show-toplevel >"$FAKE_CODEX_RECORD_DIR/git-root"
    git -C "$review_cwd" status --porcelain >"$FAKE_CODEX_RECORD_DIR/git-status"
  fi
  if [ -n "$output_file" ]; then
    printf '%s' "${FAKE_CODEX_OUTPUT-No actionable findings.}" >"$output_file"
  fi
  exit "${FAKE_CODEX_EXIT:-0}"
fi

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORKSPACE_INSTALLER="$SOURCE_ROOT/scripts/install-workspace-workflow.sh"
DIRECT_INSTALLER="$SOURCE_ROOT/scripts/install-agent-workflow.sh"

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

run_workspace_installer() {
  (cd "$1" && "$WORKSPACE_INSTALLER")
}

run_direct_installer() {
  (cd "$1" && "$DIRECT_INSTALLER")
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

prepare_workspace_review() {
  local directory="$1"
  mkdir -p "$directory/workspace"
  init_repo "$directory/workspace/service-a"
  init_repo "$directory/workspace/service-b"
  run_workspace_installer "$directory/workspace" >/dev/null
  printf '# Slice\n\nGoal: Review change\n\nScope: service-a\n\nOut: service-b\n\nTests: true\n\nContract:\n' >"$directory/workspace/service-a/.agent/current-slice.md"
  printf 'change\n' >"$directory/workspace/service-a/change.txt"
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
  assert_not_exists "$SOURCE_ROOT/templates/workspace/AGENTS.md"
  assert_not_exists "$SOURCE_ROOT/templates/workspace/CLAUDE.md"
  assert_contains "$SOURCE_ROOT/AGENTS.md" '# Workflow Repository Development'
  assert_not_contains "$SOURCE_ROOT/AGENTS.md" '# Codex Reviewer'
  assert_contains "$SOURCE_ROOT/CLAUDE.md" '# Workflow Repository Development'
  assert_not_contains "$SOURCE_ROOT/CLAUDE.md" '# Claude Implementer'
  assert_contains "$SOURCE_ROOT/AGENTS.md" 'Do not install or execute the generated workflow'
  assert_contains "$SOURCE_ROOT/CLAUDE.md" 'Do not start the generated review loop'
  assert_not_exists "$SOURCE_ROOT/.codex/rules/agent-workflow.rules"
  assert_not_exists "$SOURCE_ROOT/IMPLEMENTER.md"
  assert_not_exists "$SOURCE_ROOT/TASK_PLAN.md"
}

test_workspace_one_and_two_repositories() {
  local directory="$TEST_ROOT/workspace-counts"
  mkdir -p "$directory/one" "$directory/two/not-a-repository"
  init_repo "$directory/one/service-a"
  init_repo "$directory/two/service-a"
  init_repo "$directory/two/service-b"
  run_workspace_installer "$directory/one" >"$directory/one-output"
  run_workspace_installer "$directory/two" >"$directory/two-output"
  assert_file "$directory/one/AGENTS.md"
  assert_file "$directory/one/service-a/.agent/AGENTS.md"
  assert_file "$directory/two/service-a/.agent/AGENTS.md"
  assert_file "$directory/two/service-b/.agent/AGENTS.md"
  assert_not_exists "$directory/two/not-a-repository/.agent"
  assert_contains "$directory/two-output" '- service-a'
  assert_contains "$directory/two-output" '- service-b'
}

test_workspace_rejects_invalid_roots() {
  local directory="$TEST_ROOT/workspace-invalid"
  mkdir -p "$directory/empty"
  if run_workspace_installer "$directory/empty" >"$directory/empty.log" 2>&1; then return 1; fi
  assert_not_exists "$directory/empty/AGENTS.md"

  mkdir -p "$directory/git-workspace"
  init_repo "$directory/git-workspace"
  init_repo "$directory/git-workspace/service-a"
  if run_workspace_installer "$directory/git-workspace" >"$directory/git.log" 2>&1; then return 1; fi

  init_repo "$directory/parent"
  mkdir -p "$directory/parent/work-item"
  init_repo "$directory/parent/work-item/service-a"
  if run_workspace_installer "$directory/parent/work-item" >"$directory/parent.log" 2>&1; then return 1; fi
  assert_not_exists "$directory/parent/work-item/AGENTS.md"
}

test_workspace_worktrees_and_spaces() {
  local directory="$TEST_ROOT/worktrees and spaces"
  mkdir -p "$directory/workspace with spaces"
  init_repo "$directory/source repository"
  git -C "$directory/source repository" worktree add -q -b ticket "$directory/workspace with spaces/service worktree"
  run_workspace_installer "$directory/workspace with spaces" >/dev/null
  assert_file "$directory/workspace with spaces/service worktree/.agent/AGENTS.md"
  assert_contains "$(exclude_file "$directory/workspace with spaces/service worktree")" '.agent/'
}

test_workspace_idempotency_and_mutable_preservation() {
  local directory="$TEST_ROOT/workspace-idempotent"
  mkdir -p "$directory/workspace"
  init_repo "$directory/workspace/service-a"
  run_workspace_installer "$directory/workspace" >/dev/null
  printf 'custom plan\n' >"$directory/workspace/TASK_PLAN.md"
  printf 'custom request\n' >"$directory/workspace/.agent/initial-request.md"
  printf 'custom history\n' >"$directory/workspace/.agent/review-history.md"
  printf 'custom slice\n' >"$directory/workspace/service-a/.agent/current-slice.md"
  printf '1\n' >"$directory/workspace/service-a/.agent/review-attempts"
  run_workspace_installer "$directory/workspace" >/dev/null
  assert_eq "$(sed -n '1p' "$directory/workspace/TASK_PLAN.md")" 'custom plan'
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/initial-request.md")" 'custom request'
  assert_eq "$(sed -n '1p' "$directory/workspace/.agent/review-history.md")" 'custom history'
  assert_eq "$(sed -n '1p' "$directory/workspace/service-a/.agent/current-slice.md")" 'custom slice'
  assert_eq "$(sed -n '1p' "$directory/workspace/service-a/.agent/review-attempts")" '1'
  assert_eq "$(grep -xcF '.agent/' "$(exclude_file "$directory/workspace/service-a")")" '1'
}

test_workspace_static_conflicts_are_atomic() {
  local directory="$TEST_ROOT/workspace-collision"
  mkdir -p "$directory/workspace"
  init_repo "$directory/workspace/service-a"
  mkdir -p "$directory/workspace/service-a/.agent"
  printf 'conflict\n' >"$directory/workspace/service-a/.agent/AGENTS.md"
  if run_workspace_installer "$directory/workspace" >"$directory/output" 2>&1; then return 1; fi
  assert_not_exists "$directory/workspace/AGENTS.md"
  assert_not_exists "$directory/workspace/TASK_PLAN.md"
  assert_not_exists "$directory/workspace/service-a/.agent/current-slice.md"
}

test_workspace_preserves_project_instructions_and_excludes() {
  local directory="$TEST_ROOT/workspace-project-files"
  mkdir -p "$directory/workspace"
  init_repo "$directory/workspace/service-a"
  init_repo "$directory/workspace/service-b"
  printf 'project agents\n' >"$directory/workspace/service-a/AGENTS.md"
  printf 'project claude\n' >"$directory/workspace/service-a/CLAUDE.md"
  cp "$directory/workspace/service-a/AGENTS.md" "$directory/agents.before"
  cp "$directory/workspace/service-a/CLAUDE.md" "$directory/claude.before"
  run_workspace_installer "$directory/workspace" >/dev/null
  cmp -s "$directory/agents.before" "$directory/workspace/service-a/AGENTS.md"
  cmp -s "$directory/claude.before" "$directory/workspace/service-a/CLAUDE.md"
  assert_not_exists "$directory/workspace/service-b/AGENTS.md"
  assert_not_exists "$directory/workspace/service-b/CLAUDE.md"
  assert_file "$directory/workspace/service-a/.agent/AGENTS.md"
  local excludes
  excludes="$(exclude_file "$directory/workspace/service-a")"
  assert_contains "$excludes" '.agent/'
  assert_not_contains "$excludes" 'AGENTS.md'
  assert_not_contains "$excludes" 'CLAUDE.md'
}

test_workspace_skips_source_repository_child() {
  local directory="$TEST_ROOT/source-child"
  local workspace="$directory/workspace"
  mkdir -p "$workspace/workflow-source"
  cp -R "$SOURCE_ROOT/templates" "$workspace/workflow-source/templates"
  cp -R "$SOURCE_ROOT/scripts" "$workspace/workflow-source/scripts"
  init_repo "$workspace/workflow-source"
  git -C "$workspace/workflow-source" add templates scripts
  git -C "$workspace/workflow-source" commit -qm source
  init_repo "$workspace/service-a"
  (cd "$workspace" && "$workspace/workflow-source/scripts/install-workspace-workflow.sh") >/dev/null
  assert_not_exists "$workspace/workflow-source/.agent"
  assert_file "$workspace/service-a/.agent/AGENTS.md"
}

test_direct_installer_roots_and_worktree() {
  local directory="$TEST_ROOT/direct-roots"
  init_repo "$directory/repository"
  run_direct_installer "$directory/repository" >/dev/null
  assert_file "$directory/repository/.agent/AGENTS.md"
  mkdir -p "$directory/repository/subdirectory"
  if run_direct_installer "$directory/repository/subdirectory" >"$directory/sub.log" 2>&1; then return 1; fi
  mkdir -p "$directory/not-git"
  if run_direct_installer "$directory/not-git" >"$directory/no.log" 2>&1; then return 1; fi

  init_repo "$directory/source"
  git -C "$directory/source" worktree add -q -b direct-worktree "$directory/worktree"
  run_direct_installer "$directory/worktree" >/dev/null
  assert_file "$directory/worktree/.agent/AGENTS.md"
}

test_direct_preserves_mutable_state_and_excludes() {
  local directory="$TEST_ROOT/direct-idempotent"
  init_repo "$directory/repository"
  run_direct_installer "$directory/repository" >/dev/null
  printf 'custom plan\n' >"$directory/repository/TASK_PLAN.md"
  printf 'custom slice\n' >"$directory/repository/.agent/current-slice.md"
  printf '2\n' >"$directory/repository/.agent/review-attempts"
  run_direct_installer "$directory/repository" >/dev/null
  assert_eq "$(sed -n '1p' "$directory/repository/TASK_PLAN.md")" 'custom plan'
  assert_eq "$(sed -n '1p' "$directory/repository/.agent/current-slice.md")" 'custom slice'
  assert_eq "$(sed -n '1p' "$directory/repository/.agent/review-attempts")" '2'
  local excludes
  excludes="$(exclude_file "$directory/repository")"
  assert_eq "$(grep -xcF '.agent/' "$excludes")" '1'
  assert_eq "$(grep -xcF 'AGENTS.md' "$excludes")" '1'
}

test_direct_rejects_project_instructions() {
  local directory="$TEST_ROOT/direct-project-files"
  init_repo "$directory/agents"
  printf 'project owned\n' >"$directory/agents/AGENTS.md"
  if run_direct_installer "$directory/agents" >"$directory/agents.log" 2>&1; then return 1; fi
  assert_contains "$directory/agents.log" 'Use install-workspace-workflow.sh from a parent workspace instead.'
  assert_not_exists "$directory/agents/.agent"

  init_repo "$directory/claude"
  printf 'project owned\n' >"$directory/claude/CLAUDE.md"
  if run_direct_installer "$directory/claude" >"$directory/claude.log" 2>&1; then return 1; fi
  assert_contains "$directory/claude.log" 'Use install-workspace-workflow.sh from a parent workspace instead.'
  assert_not_exists "$directory/claude/.agent"
}

test_review_mode_argument_validation() {
  local directory="$TEST_ROOT/review-arguments"
  prepare_workspace_review "$directory"
  local script="$directory/workspace/scripts/codex-review.sh"
  if "$script" >"$directory/no-arg.log" 2>&1; then return 1; fi
  if "$script" service-a service-b >"$directory/many.log" 2>&1; then return 1; fi
  if "$script" 'service-a/nested' >"$directory/nested.log" 2>&1; then return 1; fi
  if "$script" '..' >"$directory/dotdot.log" 2>&1; then return 1; fi
  if "$script" '/tmp' >"$directory/outside.log" 2>&1; then return 1; fi
  mkdir -p "$directory/workspace/not-git"
  if "$script" not-git >"$directory/not-git.log" 2>&1; then return 1; fi
  assert_eq "$(sed -n '1p' "$directory/workspace/service-a/.agent/review-attempts")" '0'

  local direct="$directory/direct"
  init_repo "$direct"
  run_direct_installer "$direct" >/dev/null
  printf '# Slice\nGoal: direct\n' >"$direct/.agent/current-slice.md"
  printf 'change\n' >"$direct/change.txt"
  if "$direct/scripts/codex-review.sh" extra >"$directory/direct-arg.log" 2>&1; then return 1; fi
  local fake_bin
  fake_bin="$(make_fake_path "$directory/fake-direct")"
  run_fake_review "$directory/fake-direct" "$direct/scripts/codex-review.sh" >/dev/null
  assert_eq "$(sed -n '1p' "$directory/fake-direct/records/review-cwd")" "$direct/.agent"
}

test_workspace_review_targets_only_selected_repository() {
  local directory="$TEST_ROOT/review-target"
  prepare_workspace_review "$directory"
  printf 'sibling change\n' >"$directory/workspace/service-b/sibling.txt"
  local fake_bin
  fake_bin="$(make_fake_path "$directory/fake")"
  run_fake_review "$directory/fake" "$directory/workspace/scripts/codex-review.sh" service-a >/dev/null
  assert_eq "$(sed -n '1p' "$directory/fake/records/review-cwd")" "$directory/workspace/service-a/.agent"
  assert_eq "$(sed -n '1p' "$directory/fake/records/git-root")" "$directory/workspace/service-a"
  assert_contains "$directory/fake/records/args" 'review'
  assert_contains "$directory/fake/records/args" '--uncommitted'
  assert_contains "$directory/fake/records/git-status" 'change.txt'
  assert_not_contains "$directory/fake/records/git-status" 'sibling.txt'
  assert_file "$directory/workspace/service-a/.agent/latest-codex-review.md"
  assert_not_exists "$directory/workspace/service-b/.agent/latest-codex-review.md"
  assert_eq "$(sed -n '1p' "$directory/workspace/service-b/.agent/review-attempts")" '0'
}

test_review_attempt_limit() {
  local directory="$TEST_ROOT/review-limit"
  prepare_workspace_review "$directory"
  rm "$directory/workspace/service-a/.agent/review-attempts"
  make_fake_path "$directory/fake" >/dev/null
  local script="$directory/workspace/scripts/codex-review.sh"
  run_fake_review "$directory/fake" "$script" service-a >/dev/null
  assert_eq "$(sed -n '1p' "$directory/workspace/service-a/.agent/review-attempts")" '1'
  run_fake_review "$directory/fake" "$script" service-a >/dev/null
  assert_eq "$(sed -n '1p' "$directory/workspace/service-a/.agent/review-attempts")" '2'
  if run_fake_review "$directory/fake" "$script" service-a >"$directory/third.log" 2>&1; then return 1; fi
  assert_eq "$(sed -n '1p' "$directory/fake/records/count")" '2'
  assert_contains "$directory/third.log" 'Review limit reached for this slice: 2/2.'
  assert_contains "$directory/third.log" 'Mark the task Blocked and ask the user to intervene.'
}

test_review_validation_does_not_increment() {
  local directory="$TEST_ROOT/review-validation"
  prepare_workspace_review "$directory"
  cp "$SOURCE_ROOT/templates/repository/current-slice.md.tmpl" "$directory/workspace/service-a/.agent/current-slice.md"
  make_fake_path "$directory/fake" >/dev/null
  if run_fake_review "$directory/fake" "$directory/workspace/scripts/codex-review.sh" service-a >"$directory/output" 2>&1; then return 1; fi
  assert_eq "$(sed -n '1p' "$directory/workspace/service-a/.agent/review-attempts")" '0'
  assert_not_exists "$directory/fake/records/count"

  printf '# Slice\nGoal: valid\n' >"$directory/workspace/service-a/.agent/current-slice.md"
  printf 'invalid\n' >"$directory/workspace/service-a/.agent/review-attempts"
  if run_fake_review "$directory/fake" "$directory/workspace/scripts/codex-review.sh" service-a >"$directory/invalid" 2>&1; then return 1; fi
  assert_eq "$(sed -n '1p' "$directory/workspace/service-a/.agent/review-attempts")" 'invalid'
  assert_not_exists "$directory/fake/records/count"
}

test_failed_and_empty_reviews_consume_attempts() {
  local directory="$TEST_ROOT/review-failures"
  prepare_workspace_review "$directory/nonzero"
  make_fake_path "$directory/nonzero/fake" >/dev/null
  TEST_CODEX_EXIT=7
  if run_fake_review "$directory/nonzero/fake" "$directory/nonzero/workspace/scripts/codex-review.sh" service-a >"$directory/nonzero/output" 2>&1; then return 1; fi
  unset TEST_CODEX_EXIT
  assert_eq "$(sed -n '1p' "$directory/nonzero/workspace/service-a/.agent/review-attempts")" '1'
  assert_not_exists "$directory/nonzero/workspace/service-a/.agent/latest-codex-review.md"
  assert_file "$directory/nonzero/workspace/service-a/.agent/latest-codex-review-run.log"

  prepare_workspace_review "$directory/empty"
  printf 'stale clean review\n' >"$directory/empty/workspace/service-a/.agent/latest-codex-review.md"
  make_fake_path "$directory/empty/fake" >/dev/null
  TEST_CODEX_OUTPUT=''
  if run_fake_review "$directory/empty/fake" "$directory/empty/workspace/scripts/codex-review.sh" service-a >"$directory/empty/output" 2>&1; then return 1; fi
  unset TEST_CODEX_OUTPUT
  assert_eq "$(sed -n '1p' "$directory/empty/workspace/service-a/.agent/review-attempts")" '1'
  assert_not_exists "$directory/empty/workspace/service-a/.agent/latest-codex-review.md"
  assert_eq "$(sed -n '1p' "$directory/empty/workspace/service-a/.agent/previous-codex-review.md")" 'stale clean review'
}

test_review_artifact_rotation_and_success() {
  local directory="$TEST_ROOT/review-artifacts"
  prepare_workspace_review "$directory"
  printf 'old clean review\n' >"$directory/workspace/service-a/.agent/latest-codex-review.md"
  printf 'stale pending\n' >"$directory/workspace/service-a/.agent/pending-codex-review.md"
  make_fake_path "$directory/fake" >/dev/null
  TEST_CODEX_OUTPUT='new review'
  run_fake_review "$directory/fake" "$directory/workspace/scripts/codex-review.sh" service-a >/dev/null
  unset TEST_CODEX_OUTPUT
  assert_eq "$(sed -n '1p' "$directory/workspace/service-a/.agent/previous-codex-review.md")" 'old clean review'
  assert_eq "$(sed -n '1p' "$directory/workspace/service-a/.agent/latest-codex-review.md")" 'new review'
  assert_not_exists "$directory/workspace/service-a/.agent/pending-codex-review.md"
}

test_templates_capture_required_policy() {
  local codex="$SOURCE_ROOT/templates/workspace/AGENTS.md.tmpl"
  local claude="$SOURCE_ROOT/templates/workspace/CLAUDE.md.tmpl"
  local reviewer="$SOURCE_ROOT/templates/repository/AGENTS.md.tmpl"
  local implementer="$SOURCE_ROOT/templates/workspace/IMPLEMENTER.md.tmpl"
  assert_contains "$codex" '# Codex Implementer'
  assert_contains "$claude" '# Claude Implementer'
  assert_contains "$codex" 'root `AGENTS.md` and `CLAUDE.md`'
  assert_contains "$claude" 'root `AGENTS.md` and `CLAUDE.md`'
  assert_contains "$codex" '.agent/AGENTS.md`; it is for the independent reviewer only'
  assert_contains "$claude" '.agent/AGENTS.md`; it is for the independent reviewer only'
  assert_contains "$reviewer" '- edit files'
  assert_contains "$reviewer" '- run mutating commands'
  assert_contains "$implementer" 'at most two Codex review attempts per slice'
  assert_contains "$implementer" 'Caveman in Lite mode'
  assert_contains "$implementer" 'Ponytail'
  assert_contains "$implementer" 'Use the fewest words'
  assert_contains "$implementer" 'WORKSPACE_ROOT="$(pwd -P)"'
  assert_contains "$implementer" '--base staging'
  assert_contains "$implementer" '--title "$WORK_ITEM"'
  assert_contains "$implementer" 'promotion PRs from `staging` to `release`'
  assert_contains "$implementer" 'without explicit user approval'
  assert_contains "$implementer" 'The overall slice is clean only when every changed repository has a clean latest review.'
}

run_test 'source templates are isolated from active instructions' test_source_template_isolation
run_test 'workspace installer handles one and two repositories' test_workspace_one_and_two_repositories
run_test 'workspace installer rejects invalid roots' test_workspace_rejects_invalid_roots
run_test 'workspace installer supports worktrees and spaces' test_workspace_worktrees_and_spaces
run_test 'workspace installation is idempotent and preserves mutable state' test_workspace_idempotency_and_mutable_preservation
run_test 'workspace static conflicts fail before mutation' test_workspace_static_conflicts_are_atomic
run_test 'workspace preserves project instructions and excludes only .agent' test_workspace_preserves_project_instructions_and_excludes
run_test 'workspace installer skips its own source repository child' test_workspace_skips_source_repository_child
run_test 'direct installer validates roots and supports worktrees' test_direct_installer_roots_and_worktree
run_test 'direct installer preserves mutable state and excludes idempotently' test_direct_preserves_mutable_state_and_excludes
run_test 'direct installer rejects project-owned instructions' test_direct_rejects_project_instructions
run_test 'review modes validate argument counts and direct mode' test_review_mode_argument_validation
run_test 'workspace review targets only the selected repository' test_workspace_review_targets_only_selected_repository
run_test 'review attempts stop after two launches' test_review_attempt_limit
run_test 'review validation failures do not consume attempts' test_review_validation_does_not_increment
run_test 'failed and empty reviews consume attempts without approval' test_failed_and_empty_reviews_consume_attempts
run_test 'successful reviews rotate and replace artifacts' test_review_artifact_rotation_and_success
run_test 'templates capture branch, PR, review, skill, and role policy' test_templates_capture_required_policy

printf '\n%s passed; %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
