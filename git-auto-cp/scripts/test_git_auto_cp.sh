#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/git_auto_cp.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain '$needle'\nActual:\n$haystack"
}
assert_not_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected output not to contain '$needle'\nActual:\n$haystack"
}

setup_repo() {
  TMPDIR_AUTO_CP="$(mktemp -d)"
  git init --bare "$TMPDIR_AUTO_CP/origin.git" >/dev/null
  git clone "$TMPDIR_AUTO_CP/origin.git" "$TMPDIR_AUTO_CP/repo" >/dev/null 2>&1
  cd "$TMPDIR_AUTO_CP/repo"
  git config user.name "Me"
  git config user.email "me@example.com"

  printf 'base\n' > app.txt
  git add app.txt
  git commit -m "base" >/dev/null
  git branch -M prod
  git checkout -b test >/dev/null
  # 在 test 上创建一个与 feature 相同 patch 的提交作为锚点
  printf 'anchor\n' > anchor.txt
  git add anchor.txt
  git commit -m "sync anchor" >/dev/null
  git push -u origin test >/dev/null 2>&1
  git checkout prod >/dev/null
  git checkout -b feature/demo >/dev/null
  # 在 feature 上创建相同 patch 的提交（git cherry 会标记为 -）
  printf 'anchor\n' > anchor.txt
  git add anchor.txt
  git commit -m "sync anchor" >/dev/null
}

setup_repo_without_anchor() {
  TMPDIR_AUTO_CP="$(mktemp -d)"
  git init --bare "$TMPDIR_AUTO_CP/origin.git" >/dev/null
  git clone "$TMPDIR_AUTO_CP/origin.git" "$TMPDIR_AUTO_CP/repo" >/dev/null 2>&1
  cd "$TMPDIR_AUTO_CP/repo"
  git config user.name "Me"
  git config user.email "me@example.com"

  printf 'base\n' > app.txt
  git add app.txt
  git commit -m "base" >/dev/null
  git branch -M prod
  git checkout -b test >/dev/null
  git push -u origin test >/dev/null 2>&1
  git checkout prod >/dev/null
  git checkout -b feature/demo >/dev/null
}

cleanup_repo() {
  cd / >/dev/null
  rm -rf "${TMPDIR_AUTO_CP:-}"
}

test_plan_filters_commits_after_anchor_by_patch_author_and_merge() {
  setup_repo
  trap cleanup_repo RETURN

  printf 'me one\n' >> app.txt
  git add app.txt
  git commit -m "me one" >/dev/null
  local me_one
  me_one="$(git rev-parse --short HEAD)"

  git config user.email "other@example.com"
  printf 'other\n' >> app.txt
  git add app.txt
  git commit -m "other commit" >/dev/null
  local other_commit
  other_commit="$(git rev-parse --short HEAD)"

  git config user.email "me@example.com"
  git checkout -b side >/dev/null
  printf 'side\n' >> side.txt
  git add side.txt
  git commit -m "side change" >/dev/null
  git checkout feature/demo >/dev/null
  git merge --no-ff side -m "merge side" >/dev/null
  local merge_commit
  merge_commit="$(git rev-parse --short HEAD)"

  printf 'me two\n' >> app.txt
  git add app.txt
  git commit -m "me two" >/dev/null
  local me_two
  me_two="$(git rev-parse --short HEAD)"

  local output
  output="$(bash "$SCRIPT" plan test)"

  assert_contains "$output" "最近已搬运锚点"
  assert_contains "$output" "可 cherry-pick: 2"
  assert_contains "$output" "$me_one"
  assert_contains "$output" "$me_two"
  assert_not_contains "$output" "other commit"
  assert_contains "$output" "跳过 merge commit: 1"
  assert_contains "$output" "$merge_commit"
}

test_plan_uses_latest_cherry_minus_anchor_and_only_lists_newer_commits() {
  setup_repo_without_anchor
  trap cleanup_repo RETURN

  # 在 test 上创建一个提交（patch-id 将与 feature 上的匹配）
  git checkout test >/dev/null
  printf 'same\n' > anchor.txt
  git add anchor.txt
  git commit -m "cherry anchor" >/dev/null
  git push -u origin test >/dev/null 2>&1

  # 在 feature 上创建相同 patch 的提交（git cherry 会标记为 -）
  git checkout feature/demo >/dev/null
  printf 'same\n' > anchor.txt
  git add anchor.txt
  git commit -m "cherry anchor" >/dev/null
  local anchor
  anchor="$(git rev-parse --short HEAD)"

  # 再创建一个不同 patch 的提交（git cherry 会标记为 +）
  printf 'feature different\n' > shared.txt
  git add shared.txt
  git commit -m "✅ test(storehouseSpotCheck): 添加仓抽检 DTO/Entity 单元测试" >/dev/null
  local old_different
  old_different="$(git rev-parse --short HEAD)"

  # 最后一个新提交
  printf 'new\n' > new.txt
  git add new.txt
  git commit -m "new commit" >/dev/null
  local new_commit
  new_commit="$(git rev-parse --short HEAD)"

  local output
  output="$(bash "$SCRIPT" plan test)"

  assert_contains "$output" "最近已搬运锚点"
  assert_contains "$output" "可 cherry-pick: 2"
  assert_contains "$output" "$old_different"
  assert_contains "$output" "$new_commit"
}

test_plan_finds_cherry_anchor_from_target_non_first_parent() {
  setup_repo_without_anchor
  trap cleanup_repo RETURN

  git checkout test >/dev/null
  git checkout -b target-side >/dev/null
  printf 'same side anchor\n' > side-anchor.txt
  git add side-anchor.txt
  git commit -m "target side anchor" >/dev/null
  git checkout test >/dev/null
  printf 'target first parent\n' > target.txt
  git add target.txt
  git commit -m "target first parent" >/dev/null
  git merge --no-ff target-side -m "merge target side" >/dev/null
  git push -u origin test >/dev/null 2>&1

  git checkout feature/demo >/dev/null
  printf 'same side anchor\n' > side-anchor.txt
  git add side-anchor.txt
  git commit -m "side anchor" >/dev/null
  local anchor
  anchor="$(git rev-parse --short HEAD)"

  printf 'new\n' > new.txt
  git add new.txt
  git commit -m "new after non-first-parent anchor" >/dev/null
  local new_commit
  new_commit="$(git rev-parse --short HEAD)"

  local output
  output="$(bash "$SCRIPT" plan test)"

  assert_contains "$output" "最近已搬运锚点: $anchor"
  assert_contains "$output" "git cherry 匹配"
  assert_contains "$output" "可 cherry-pick: 1"
  assert_contains "$output" "$new_commit"
}

test_plan_uses_metadata_equal_anchor_when_patch_id_differs() {
  setup_repo_without_anchor
  trap cleanup_repo RETURN

  local anchor_date
  anchor_date="$(date +%Y-%m-%dT%H:%M:%S%z)"

  git checkout test >/dev/null
  printf 'target context\n' > app.txt
  git add app.txt
  git -c user.email=other@example.com commit -m "target context" >/dev/null
  GIT_AUTHOR_DATE="$anchor_date" GIT_COMMITTER_DATE="$anchor_date" \
    bash -c 'printf "target logical change\n" > app.txt && git add app.txt && git commit -m "same logical commit"' >/dev/null
  git push -u origin test >/dev/null 2>&1

  git checkout feature/demo >/dev/null
  GIT_AUTHOR_DATE="$anchor_date" GIT_COMMITTER_DATE="$anchor_date" \
    bash -c 'printf "source logical change\n" > app.txt && git add app.txt && git commit -m "same logical commit"' >/dev/null
  local anchor
  anchor="$(git rev-parse --short HEAD)"

  printf 'new\n' > new.txt
  git add new.txt
  git commit -m "new after metadata anchor" >/dev/null
  local new_commit
  new_commit="$(git rev-parse --short HEAD)"

  local output
  output="$(bash "$SCRIPT" plan test)"

  assert_contains "$output" "最近已搬运锚点: $anchor"
  assert_contains "$output" "元数据匹配"
  assert_contains "$output" "可 cherry-pick: 1"
  assert_contains "$output" "$new_commit"
}

test_plan_uses_metadata_anchor_from_target_non_first_parent() {
  setup_repo_without_anchor
  trap cleanup_repo RETURN

  local anchor_date
  anchor_date="$(date +%Y-%m-%dT%H:%M:%S%z)"

  git checkout test >/dev/null
  git checkout -b target-side >/dev/null
  GIT_AUTHOR_DATE="$anchor_date" GIT_COMMITTER_DATE="$anchor_date" \
    bash -c 'printf "target logical change\n" > app.txt && git add app.txt && git commit -m "same logical commit"' >/dev/null
  git checkout test >/dev/null
  printf 'target first parent\n' > target.txt
  git add target.txt
  git commit -m "target first parent" >/dev/null
  git merge --no-ff target-side -m "merge target side" >/dev/null
  git push -u origin test >/dev/null 2>&1

  git checkout feature/demo >/dev/null
  GIT_AUTHOR_DATE="$anchor_date" GIT_COMMITTER_DATE="$anchor_date" \
    bash -c 'printf "source logical change\n" > app.txt && git add app.txt && git commit -m "same logical commit"' >/dev/null
  local anchor
  anchor="$(git rev-parse --short HEAD)"

  printf 'new\n' > new.txt
  git add new.txt
  git commit -m "new after non-first-parent metadata anchor" >/dev/null
  local new_commit
  new_commit="$(git rev-parse --short HEAD)"

  local output
  output="$(bash "$SCRIPT" plan test)"

  assert_contains "$output" "最近已搬运锚点: $anchor"
  assert_contains "$output" "元数据匹配"
  assert_contains "$output" "可 cherry-pick: 1"
  assert_contains "$output" "$new_commit"
}

test_plan_reports_pre_anchor_unpicked_commits() {
  setup_repo_without_anchor
  trap cleanup_repo RETURN

  git checkout test >/dev/null
  printf 'same\n' > anchor.txt
  git add anchor.txt
  git commit -m "cherry anchor" >/dev/null
  git push -u origin test >/dev/null 2>&1

  git checkout feature/demo >/dev/null
  printf 'old missing\n' > old-missing.txt
  git add old-missing.txt
  git commit -m "old missing before anchor" >/dev/null
  local old_missing
  old_missing="$(git rev-parse --short HEAD)"

  printf 'same\n' > anchor.txt
  git add anchor.txt
  git commit -m "cherry anchor" >/dev/null

  printf 'new\n' > new.txt
  git add new.txt
  git commit -m "new after anchor" >/dev/null
  local new_commit
  new_commit="$(git rev-parse --short HEAD)"

  local output
  output="$(bash "$SCRIPT" plan test)"

  assert_contains "$output" "可 cherry-pick: 1"
  assert_contains "$output" "$new_commit"
  assert_contains "$output" "锚点前未搬运提交"
  assert_contains "$output" "$old_missing"
  assert_contains "$output" "old missing before anchor"
}

test_plan_preflight_reports_cherry_pick_conflict() {
  setup_repo_without_anchor
  trap cleanup_repo RETURN

  git checkout test >/dev/null
  printf 'same\n' > anchor.txt
  git add anchor.txt
  git commit -m "cherry anchor" >/dev/null
  printf 'target\n' > app.txt
  git add app.txt
  git commit -m "target app change" >/dev/null
  git push -u origin test >/dev/null 2>&1

  git checkout feature/demo >/dev/null
  printf 'same\n' > anchor.txt
  git add anchor.txt
  git commit -m "cherry anchor" >/dev/null
  printf 'source\n' > app.txt
  git add app.txt
  git commit -m "source app change" >/dev/null
  local conflict_commit
  conflict_commit="$(git rev-parse --short HEAD)"

  local output
  output="$(bash "$SCRIPT" plan test)"

  assert_contains "$output" "可 cherry-pick: 1"
  assert_contains "$output" "预检 cherry-pick 冲突: 1"
  assert_contains "$output" "$conflict_commit"
  assert_contains "$output" "source app change"
}

test_plan_stops_when_no_cherry_anchor_exists() {
  setup_repo_without_anchor
  trap cleanup_repo RETURN

  # test 和 feature 没有任何 patch-id 匹配的提交
  git checkout test >/dev/null
  GIT_AUTHOR_DATE="2026-06-24T10:00:00+0800" GIT_COMMITTER_DATE="2026-06-24T10:00:00+0800" \
    bash -c 'printf "target\n" > shared.txt && git add shared.txt && git commit -m "same subject"' >/dev/null
  git push -u origin test >/dev/null 2>&1

  git checkout feature/demo >/dev/null
  GIT_AUTHOR_DATE="2026-06-24T11:00:00+0800" GIT_COMMITTER_DATE="2026-06-24T11:00:00+0800" \
    bash -c 'printf "feature\n" > shared.txt && git add shared.txt && git commit -m "same subject"' >/dev/null

  set +e
  local output status
  output="$(bash "$SCRIPT" plan test 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected plan to fail when no cherry anchor exists"
  assert_contains "$output" "ANCHOR_NOT_FOUND"
}

test_plan_with_since_includes_start_commit() {
  setup_repo_without_anchor
  trap cleanup_repo RETURN

  # feature 上有3个提交，没有锚点
  printf 'a\n' > a.txt
  git add a.txt
  git commit -m "commit a" >/dev/null
  local commit_a
  commit_a="$(git rev-parse HEAD)"

  printf 'b\n' > b.txt
  git add b.txt
  git commit -m "commit b" >/dev/null

  printf 'c\n' > c.txt
  git add c.txt
  git commit -m "commit c" >/dev/null
  local commit_c
  commit_c="$(git rev-parse --short HEAD)"

  # 不用 --since 应该失败
  set +e
  output="$(bash "$SCRIPT" plan test 2>&1)"
  status=$?
  set -e
  [[ $status -ne 0 ]] || fail "expected plan to fail without --since"
  assert_contains "$output" "ANCHOR_NOT_FOUND"

  # 用 --since 指定 commit a 作为起始提交，应该包含 a 本身
  output="$(bash "$SCRIPT" plan test --since "$commit_a")"
  assert_contains "$output" "手动指定起始提交"
  assert_contains "$output" "包含自身"
  assert_contains "$output" "可 cherry-pick: 3"
  assert_contains "$output" "commit a"
  assert_contains "$output" "commit b"
  assert_contains "$output" "commit c"
}

test_plan_without_since_only_scans_recent_7_days() {
  setup_repo_without_anchor
  trap cleanup_repo RETURN

  git checkout test >/dev/null
  GIT_AUTHOR_DATE="2024-01-01T00:00:00+0800" GIT_COMMITTER_DATE="2024-01-01T00:00:00+0800" \
    bash -c 'printf "old anchor\n" > old-anchor.txt && git add old-anchor.txt && git commit -m "old anchor"' >/dev/null
  git push -u origin test >/dev/null 2>&1

  git checkout feature/demo >/dev/null
  GIT_AUTHOR_DATE="2024-01-01T00:00:00+0800" GIT_COMMITTER_DATE="2024-01-01T00:00:00+0800" \
    bash -c 'printf "old anchor\n" > old-anchor.txt && git add old-anchor.txt && git commit -m "old anchor"' >/dev/null
  printf 'new\n' > new.txt
  git add new.txt
  git commit -m "new commit" >/dev/null

  set +e
  local output status
  output="$(bash "$SCRIPT" plan test 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected plan to fail when only old anchor exists and --since is not provided"
  assert_contains "$output" "ANCHOR_NOT_FOUND"
  assert_contains "$output" "最近7天提交"
  assert_contains "$output" "--since <commit>"
}

test_auto_mode_stops_when_anchor_not_found_within_7_days() {
  setup_repo_without_anchor
  trap cleanup_repo RETURN

  git checkout test >/dev/null
  GIT_AUTHOR_DATE="2024-01-01T00:00:00+0800" GIT_COMMITTER_DATE="2024-01-01T00:00:00+0800" \
    bash -c 'printf "old anchor\n" > old-anchor.txt && git add old-anchor.txt && git commit -m "old anchor"' >/dev/null
  git push -u origin test >/dev/null 2>&1

  git checkout feature/demo >/dev/null
  GIT_AUTHOR_DATE="2024-01-01T00:00:00+0800" GIT_COMMITTER_DATE="2024-01-01T00:00:00+0800" \
    bash -c 'printf "old anchor\n" > old-anchor.txt && git add old-anchor.txt && git commit -m "old anchor"' >/dev/null
  printf 'new\n' > new.txt
  git add new.txt
  git commit -m "new commit" >/dev/null

  set +e
  local output status
  output="$(bash "$SCRIPT" plan test -a 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected auto plan to fail when anchor is older than 7 days"
  assert_contains "$output" "ANCHOR_NOT_FOUND"
  assert_contains "$output" "已限制搜索最近7天提交"
  assert_contains "$output" "--since <commit>"
}

test_run_keeps_current_worktree_branch_unchanged() {
  setup_repo
  trap cleanup_repo RETURN

  printf 'me one\n' >> app.txt
  git add app.txt
  git commit -m "me one" >/dev/null

  local before_branch output
  before_branch="$(git branch --show-current)"
  output="$(bash "$SCRIPT" run test)"

  local after_branch
  after_branch="$(git branch --show-current)"
  [[ "$after_branch" == "$before_branch" ]] || fail "expected current worktree to remain on $before_branch, got $after_branch"
  assert_contains "$output" "当前工作区未切换分支"
}

test_run_cherry_picks_and_returns_to_source_branch() {
  setup_repo
  trap cleanup_repo RETURN

  printf 'me one\n' >> app.txt
  git add app.txt
  git commit -m "me one" >/dev/null

  bash "$SCRIPT" run test >/tmp/git-auto-cp-run.out

  local branch
  branch="$(git branch --show-current)"
  [[ "$branch" == "feature/demo" ]] || fail "expected to return to feature/demo, got $branch"

  git checkout test >/dev/null
  git log --oneline --format=%s -1 | grep -q "me one" || fail "target branch does not contain cherry-picked commit"
}

test_non_feature_branch_requires_explicit_allow_even_for_run() {
  setup_repo
  trap cleanup_repo RETURN

  git checkout prod >/dev/null
  set +e
  local output status
  output="$(bash "$SCRIPT" run test -a 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected run from non-feature branch to fail without allow flag"
  assert_contains "$output" "NON_FEATURE_SOURCE_CONFIRM_REQUIRED"
}

test_dirty_non_feature_branch_requires_allow_before_worktree_clean_check() {
  setup_repo
  trap cleanup_repo RETURN

  git checkout prod >/dev/null
  printf 'dirty\n' > dirty.txt

  set +e
  local output status
  output="$(bash "$SCRIPT" plan test -a 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected dirty non-feature plan to fail without allow flag"
  assert_contains "$output" "NON_FEATURE_SOURCE_CONFIRM_REQUIRED"
  assert_not_contains "$output" "工作区不干净"
}

main() {
  test_plan_filters_commits_after_anchor_by_patch_author_and_merge
  test_plan_uses_latest_cherry_minus_anchor_and_only_lists_newer_commits
  test_plan_finds_cherry_anchor_from_target_non_first_parent
  test_plan_uses_metadata_equal_anchor_when_patch_id_differs
  test_plan_uses_metadata_anchor_from_target_non_first_parent
  test_plan_reports_pre_anchor_unpicked_commits
  test_plan_preflight_reports_cherry_pick_conflict
  test_plan_stops_when_no_cherry_anchor_exists
  test_plan_with_since_includes_start_commit
  test_plan_without_since_only_scans_recent_7_days
  test_auto_mode_stops_when_anchor_not_found_within_7_days
  test_run_keeps_current_worktree_branch_unchanged
  test_run_cherry_picks_and_returns_to_source_branch
  test_non_feature_branch_requires_explicit_allow_even_for_run
  test_dirty_non_feature_branch_requires_allow_before_worktree_clean_check
  echo "PASS"
}

main "$@"
