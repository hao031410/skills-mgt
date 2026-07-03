#!/usr/bin/env bash
set -euo pipefail

RECENT_DAYS=7

usage() {
  cat <<'USAGE'
Usage:
  git_auto_cp.sh plan <target-branch> [-p] [-a] [--allow-non-feature-source] [--since <commit>]
  git_auto_cp.sh run  <target-branch> [-p] [-a] [--allow-non-feature-source] [--since <commit>]
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

is_feature_branch() {
  [[ "$1" == feature* ]]
}

require_clean_worktree() {
  if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    git status --short >&2
    fail "工作区不干净；请先完成自动 commit 或手动 commit 后重试。使用 /git-auto-cp 时，未带 -a 应先询问是否自动 commit，带 -a 应先自动 commit 再继续"
  fi
}

short_sha() {
  git rev-parse --short "$1"
}

commit_subject() {
  git show -s --format=%s "$1"
}

commit_time() {
  git show -s --date=format:'%m-%d %H:%M' --format=%cd "$1"
}

commit_author_email() {
  git show -s --format=%ae "$1"
}

commit_author_date() {
  git show -s --format=%aI "$1"
}

parent_count() {
  git rev-list --parents -n 1 "$1" | awk '{print NF-1}'
}

metadata_parent_count() {
  local parents="$1"
  [[ -z "$parents" ]] && echo 0 && return
  awk '{print NF}' <<<"$parents"
}

find_metadata_anchor_target() {
  local source_date="$1" subject="$2" metadata_file="$3" email="$4"
  local match
  match="$(awk -F '\t' -v email="$email" -v date="$source_date" -v subject="$subject" \
    '$1 == email && $2 == date && $3 == subject {print $4; exit}' "$metadata_file")"
  if [[ -n "$match" ]]; then
    printf '%s\n' "$match"
    return 0
  fi

  return 1
}

populate_source_commit_metadata() {
  local source="$1" since_ref="${2:-}" meta_file="$3"
  if [[ -n "$since_ref" ]]; then
    git log --first-parent --format='%H%x09%P%x09%ae%x09%aI%x09%s' "$source" >"$meta_file"
    return
  fi

  git log --first-parent --since="$RECENT_DAYS.days.ago" --format='%H%x09%P%x09%ae%x09%aI%x09%s' "$source" >"$meta_file"
}

populate_source_patch_state() {
  local base_ref="$1" source="$2" since_ref="${3:-}" state_file="$4"
  local rev_args=(--right-only --cherry-mark)
  if [[ -z "$since_ref" ]]; then
    rev_args+=("--since=$RECENT_DAYS.days.ago")
  fi
  rev_args+=("$base_ref...$source")
  git rev-list "${rev_args[@]}" >"$state_file"
}

build_source_analysis() {
  local meta_file="$1" state_file="$2" analysis_file="$3"
  awk -F '\t' '
    NR == FNR {
      state[substr($0, 2)] = substr($0, 1, 1)
      next
    }
    {
      parent_count = 0
      if ($2 != "") {
        parent_count = split($2, parents, " ")
      }
      print $1 "\t" parent_count "\t" $3 "\t" $4 "\t" $5 "\t" state[$1]
    }
  ' "$state_file" "$meta_file" >"$analysis_file"
}

recent_window_hint() {
  echo "最近${RECENT_DAYS}天提交"
}

reverse_lines() {
  if command -v tac >/dev/null 2>&1; then
    tac
    return
  fi
  tail -r
}

find_latest_anchor() {
  local source="$1" base_ref="$2" email="$3" since_ref="${4:-}" source_analysis_file="$5"
  local metadata_file result=""

  # 如果用户通过 --since 指定了起始提交，直接返回；后续收集范围会包含它本身。
  if [[ -n "$since_ref" ]]; then
    local resolved
    resolved="$(git rev-parse --verify "$since_ref" 2>/dev/null)" || fail "--since 指定的 commit 不存在: $since_ref"
    printf '%s %s\n' "$resolved" "<manual>"
    return 0
  fi

  metadata_file="$(mktemp)"

  git log --since="$RECENT_DAYS.days.ago" --format='%ae%x09%aI%x09%s%x09%H' "$base_ref" >"$metadata_file"

  while IFS=$'\t' read -r sha parent_count commit_email commit_date commit_subject state; do
    [[ -n "$sha" ]] || continue
    [[ "$parent_count" -eq 1 ]] || continue
    [[ "$commit_email" == "$email" ]] || continue
    if [[ "$state" == "=" ]]; then
      result="$sha <cherry>"
      break
    fi
    if git merge-base --is-ancestor "$sha" "$base_ref" 2>/dev/null; then
      result="$sha <shared>"
      break
    fi
    local metadata_target
    if metadata_target="$(find_metadata_anchor_target "$commit_date" "$commit_subject" "$metadata_file" "$email")"; then
      result="$sha <metadata:$metadata_target>"
      break
    fi
  done <"$source_analysis_file"

  rm -f "$metadata_file"

  if [[ -n "$result" ]]; then
    printf '%s\n' "$result"
    return 0
  fi
  return 1
}

suggest_manual_since() {
  local source_analysis_file="$1" email="$2"
  awk -F '\t' -v email="$email" '$2 == 1 && $3 == email && $6 == "+" { print $1 }' "$source_analysis_file" | reverse_lines | head -n 1
}

parse_args() {
  MODE="${1:-}"
  TARGET="${2:-}"
  AUTO=false
  PUSH=false
  ALLOW_NON_FEATURE=false
  SINCE=""

  if [[ -z "$MODE" || -z "$TARGET" || "$MODE" != "plan" && "$MODE" != "run" ]]; then
    usage >&2
    exit 2
  fi
  shift 2

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--auto) AUTO=true ;;
      -p|--push) PUSH=true ;;
      --allow-non-feature-source) ALLOW_NON_FEATURE=true ;;
      --since)
        [[ $# -ge 2 ]] || fail "--since 需要指定一个 commit"
        SINCE="$2"
        shift
        ;;
      -h|--help) usage; exit 0 ;;
      *) fail "未知参数: $1" ;;
    esac
    shift
  done
}

current_branch() {
  git symbolic-ref --quiet --short HEAD || fail "当前处于 detached HEAD，无法作为源分支"
}

check_source_branch() {
  local source="$1"
  if ! is_feature_branch "$source" && [[ "$ALLOW_NON_FEATURE" != true ]]; then
    cat >&2 <<EOF
NON_FEATURE_SOURCE_CONFIRM_REQUIRED
当前源分支不是 feature 开头: $source
如确认要从该分支搬运提交，请在用户二次确认后追加 --allow-non-feature-source。
EOF
    exit 3
  fi
}

fetch_origin() {
  git fetch origin --prune >/dev/null
}

local_branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

remote_branch_exists() {
  git show-ref --verify --quiet "refs/remotes/origin/$1"
}

branch_upstream() {
  git rev-parse --abbrev-ref --symbolic-full-name "$1@{u}" 2>/dev/null || true
}

resolve_plan_base_ref() {
  local target="$1"
  if local_branch_exists "$target"; then
    local upstream
    upstream="$(branch_upstream "$target")"
    [[ -n "$upstream" ]] || fail "目标分支 $target 没有 upstream，请手动处理后重试"
    echo "$upstream"
    return
  fi

  if remote_branch_exists "$target"; then
    echo "origin/$target"
    return
  fi

  fail "目标分支不存在: $target（本地和 origin/$target 均不存在）"
}

print_commit_table() {
  local file="$1" title="$2"
  [[ -s "$file" ]] || return 0
  echo
  echo "$title"
  printf '  %s %s %s %s\n' "#" "提交" "时间" "说明"
  local index=0 sha
  while read -r sha; do
    [[ -n "$sha" ]] || continue
    index=$((index + 1))
    printf '  %s %s %s\n' "$index" "$(short_sha "$sha")" "$(commit_time "$sha")"
    printf '    说明: %s\n' "$(commit_subject "$sha")"
  done <"$file"
}

collect_commits() {
  local source="$1" email="$2" out_file="$3" present_file="$4" non_user_file="$5" merge_file="$6" anchor_ref="$7" include_anchor="${8:-false}" source_analysis_file="$9"
  : >"$out_file"
  : >"$present_file"
  : >"$non_user_file"
  : >"$merge_file"

  local order_file
  order_file="$(mktemp)"

  awk -F '\t' '$6 == "=" { print $1 }' "$source_analysis_file" >"$present_file"

  if [[ "$include_anchor" == true ]]; then
    local anchor_parent
    anchor_parent="$(git rev-parse --verify "$anchor_ref^" 2>/dev/null || true)"
    if [[ -n "$anchor_parent" ]]; then
      git rev-list --first-parent --reverse "$anchor_parent..$source" >"$order_file"
    else
      git rev-list --first-parent --reverse "$source" >"$order_file"
    fi
  else
    awk -v anchor="$anchor_ref" '
      $1 == anchor { exit }
      { print $1 }
    ' "$source_analysis_file" | reverse_lines >"$order_file"
  fi
  while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue

    local metadata_line parent_count commit_email state
    metadata_line="$(awk -F '\t' -v sha="$sha" '$1 == sha { print; exit }' "$source_analysis_file")"
    [[ -n "$metadata_line" ]] || continue
    parent_count="$(printf '%s\n' "$metadata_line" | awk -F '\t' '{print $2}')"
    commit_email="$(printf '%s\n' "$metadata_line" | awk -F '\t' '{print $3}')"
    state="$(printf '%s\n' "$metadata_line" | awk -F '\t' '{print $6}')"

    if [[ "$parent_count" -gt 1 ]]; then
      if [[ "$commit_email" == "$email" ]]; then
        echo "$sha" >>"$merge_file"
      fi
      continue
    fi

    [[ "$state" == "+" ]] || continue

    if [[ "$commit_email" != "$email" ]]; then
      echo "$sha" >>"$non_user_file"
      continue
    fi

    echo "$sha" >>"$out_file"
  done <"$order_file"

  rm -f "$order_file"
}

line_count() {
  [[ -s "$1" ]] && wc -l <"$1" | tr -d ' ' || echo 0
}

target_branch_summary() {
  local target="$1" base_ref="$2"
  if ! local_branch_exists "$target"; then
    return
  fi

  local counts ahead behind
  counts="$(git rev-list --left-right --count "$target...$base_ref" 2>/dev/null || true)"
  if [[ -n "$counts" ]]; then
    ahead="${counts%%[[:space:]]*}"
    behind="${counts##*[[:space:]]}"
    echo "本地目标分支: $target $(short_sha "$target")（相对 $base_ref: ahead ${ahead} / behind ${behind}）"
    return
  fi

  echo "本地目标分支: $target $(short_sha "$target")"
}

print_plan() {
  local mode="$1" target="$2" source="$3" base_ref="$4" commits="$5" present="$6" non_user="$7" merges="$8" source_anchor="$9" target_anchor="${10}" pre_anchor="${11}" preflight_stopped="${12}"
  local anchor_display anchor_label
  if [[ "$target_anchor" == "<manual>" ]]; then
    anchor_label="手动指定起始提交"
    anchor_display="$(short_sha "$source_anchor") (--since，包含自身)"
  elif [[ "$target_anchor" == "<cherry>" ]]; then
    anchor_label="最近已搬运锚点"
    anchor_display="$(short_sha "$source_anchor") (git cherry 匹配)"
  elif [[ "$target_anchor" == "<shared>" ]]; then
    anchor_label="最近已搬运锚点"
    anchor_display="$(short_sha "$source_anchor") (共享祖先)"
  elif [[ "$target_anchor" == \<metadata:* ]]; then
    local metadata_target
    metadata_target="${target_anchor#<metadata:}"
    metadata_target="${metadata_target%>}"
    anchor_label="最近已搬运锚点"
    anchor_display="$(short_sha "$source_anchor") <-> $(short_sha "$metadata_target") (元数据匹配) $(commit_subject "$source_anchor")"
  else
    anchor_label="最近已搬运锚点"
    anchor_display="$(short_sha "$source_anchor") <-> $(short_sha "$target_anchor") $(commit_subject "$source_anchor")"
  fi
  cat <<EOF
Git Auto Cp Plan
模式: $mode
源分支: $source
目标分支: $target
$(target_branch_summary "$target" "$base_ref")
比较基准: $base_ref $(short_sha "$base_ref")
$anchor_label: $anchor_display
当前用户邮箱: $(git config user.email)
自动 push: $PUSH

统计:
  目标分支已存在等价补丁: $(line_count "$present")
  非当前用户提交: $(line_count "$non_user")
  跳过 merge commit: $(line_count "$merges")
  锚点前未搬运提交: $(line_count "$pre_anchor")
  预检 cherry-pick 冲突: $(line_count "$preflight_stopped")
  可 cherry-pick: $(line_count "$commits")
EOF

  if [[ -s "$commits" ]]; then
    print_commit_table "$commits" "将 cherry-pick:"
  fi

  if [[ -s "$merges" ]]; then
    print_commit_table "$merges" "跳过的 merge commit:"
  fi

  if [[ -s "$pre_anchor" ]]; then
    print_commit_table "$pre_anchor" "锚点前未搬运提交（不会自动 cherry-pick）:"
  fi

  if [[ -s "$preflight_stopped" ]]; then
    print_commit_table "$preflight_stopped" "预检 cherry-pick 冲突:"
  fi
}

make_temp_files() {
  COMMITS_FILE="$(mktemp)"
  PRESENT_FILE="$(mktemp)"
  NON_USER_FILE="$(mktemp)"
  MERGE_FILE="$(mktemp)"
  PRE_ANCHOR_FILE="$(mktemp)"
  PREFLIGHT_STOPPED_FILE="$(mktemp)"
  SOURCE_META_FILE="$(mktemp)"
  PATCH_STATE_FILE="$(mktemp)"
  SOURCE_ANALYSIS_FILE="$(mktemp)"
  trap 'rm -f "$COMMITS_FILE" "$PRESENT_FILE" "$NON_USER_FILE" "$MERGE_FILE" "$PRE_ANCHOR_FILE" "$PREFLIGHT_STOPPED_FILE" "$SOURCE_META_FILE" "$PATCH_STATE_FILE" "$SOURCE_ANALYSIS_FILE"' EXIT
}

prepare_comparison_context() {
  local base_ref="$1" source="$2" since_ref="$3"
  populate_source_commit_metadata "$source" "$since_ref" "$SOURCE_META_FILE"
  populate_source_patch_state "$base_ref" "$source" "$since_ref" "$PATCH_STATE_FILE"
  build_source_analysis "$SOURCE_META_FILE" "$PATCH_STATE_FILE" "$SOURCE_ANALYSIS_FILE"
}

prepare_run_worktree() {
  local base_ref="$1"
  RUN_WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/git-auto-cp-worktree.XXXXXX")"
  git worktree add --detach "$RUN_WORKTREE" "$base_ref" >/dev/null
}

collect_pre_anchor_commits() {
  local email="$1" anchor_ref="$2" out_file="$3" source_analysis_file="$4"
  : >"$out_file"

  local older_file
  older_file="$(mktemp)"
  awk -v anchor="$anchor_ref" '
    $1 == anchor { seen=1; next }
    seen { print }
  ' "$source_analysis_file" >"$older_file"

  while IFS=$'\t' read -r sha parent_count commit_email _commit_date _commit_subject state; do
    [[ -n "$sha" ]] || continue
    [[ "$parent_count" -eq 1 ]] || continue
    [[ "$commit_email" == "$email" ]] || continue
    [[ "$state" == "+" ]] || continue
    echo "$sha" >>"$out_file"
  done <"$older_file"

  rm -f "$older_file"
}

preflight_cherry_picks() {
  local base_ref="$1" commits_file="$2" stopped_file="$3"
  : >"$stopped_file"
  [[ -s "$commits_file" ]] || return 0

  local preflight_worktree
  preflight_worktree="$(mktemp -d "${TMPDIR:-/tmp}/git-auto-cp-preflight.XXXXXX")"
  if ! git worktree add --detach "$preflight_worktree" "$base_ref" >/dev/null 2>&1; then
    rm -rf "$preflight_worktree"
    fail "无法创建预检 worktree"
  fi

  local sha
  while read -r sha; do
    [[ -n "$sha" ]] || continue
    if git -C "$preflight_worktree" cherry-pick "$sha" >/dev/null 2>&1; then
      continue
    fi
    echo "$sha" >>"$stopped_file"
    break
  done <"$commits_file"

  git worktree remove --force "$preflight_worktree" >/dev/null 2>&1 || true
  rm -rf "$preflight_worktree"
}

cleanup_run_worktree() {
  if [[ -n "${RUN_WORKTREE:-}" && -d "$RUN_WORKTREE" ]]; then
    git worktree remove --force "$RUN_WORKTREE" >/dev/null 2>&1 || true
    rm -rf "$RUN_WORKTREE"
  fi
  RUN_WORKTREE=""
}

update_local_target_branch() {
  local target="$1" new_head="$2"
  git update-ref "refs/heads/$target" "$new_head"
  if remote_branch_exists "$target"; then
    git branch --set-upstream-to="origin/$target" "$target" >/dev/null 2>&1 || true
  fi
}

push_run_worktree_head() {
  local target="$1"
  git -C "$RUN_WORKTREE" push origin "HEAD:refs/heads/$target"
}

run_plan() {
  local source base_ref email anchor_pair source_anchor target_anchor
  source="$(current_branch)"
  check_source_branch "$source"
  require_clean_worktree
  email="$(git config user.email)"
  [[ -n "$email" ]] || fail "git config user.email 为空，无法判断当前用户提交"
  fetch_origin
  base_ref="$(resolve_plan_base_ref "$TARGET")"
  make_temp_files
  prepare_comparison_context "$base_ref" "$source" "$SINCE"
  if ! anchor_pair="$(find_latest_anchor "$source" "$base_ref" "$email" "$SINCE" "$SOURCE_ANALYSIS_FILE")"; then
    echo "ANCHOR_NOT_FOUND" >&2
    if [[ -z "$SINCE" ]]; then
      local suggested_since
      suggested_since="$(suggest_manual_since "$SOURCE_ANALYSIS_FILE" "$email")"
      if [[ -n "$suggested_since" ]]; then
        echo "建议人工确认后使用 --since $(short_sha "$suggested_since")；--since 会包含该 commit 本身。" >&2
      fi
      fail "未找到最近已搬运锚点（已限制搜索$(recent_window_hint)）。请使用 --since <commit> 手动指定起始 commit"
    fi
    fail "未找到最近已搬运锚点，无法安全判断本次需要搬运的提交范围。可使用 --since <commit> 指定起始点"
  fi
  source_anchor="${anchor_pair%% *}"
  target_anchor="${anchor_pair##* }"
  collect_commits "$source" "$email" "$COMMITS_FILE" "$PRESENT_FILE" "$NON_USER_FILE" "$MERGE_FILE" "$source_anchor" "$([[ "$target_anchor" == "<manual>" ]] && echo true || echo false)" "$SOURCE_ANALYSIS_FILE"
  if [[ "$target_anchor" != "<manual>" ]]; then
    collect_pre_anchor_commits "$email" "$source_anchor" "$PRE_ANCHOR_FILE" "$SOURCE_ANALYSIS_FILE"
  fi
  preflight_cherry_picks "$base_ref" "$COMMITS_FILE" "$PREFLIGHT_STOPPED_FILE"
  print_plan "plan" "$TARGET" "$source" "$base_ref" "$COMMITS_FILE" "$PRESENT_FILE" "$NON_USER_FILE" "$MERGE_FILE" "$source_anchor" "$target_anchor" "$PRE_ANCHOR_FILE" "$PREFLIGHT_STOPPED_FILE"
}

run_execute() {
  local source email base_ref anchor_pair source_anchor target_anchor
  source="$(current_branch)"
  check_source_branch "$source"
  require_clean_worktree
  email="$(git config user.email)"
  [[ -n "$email" ]] || fail "git config user.email 为空，无法判断当前用户提交"
  fetch_origin
  base_ref="$(resolve_plan_base_ref "$TARGET")"
  make_temp_files
  prepare_comparison_context "$base_ref" "$source" "$SINCE"
  if ! anchor_pair="$(find_latest_anchor "$source" "$base_ref" "$email" "$SINCE" "$SOURCE_ANALYSIS_FILE")"; then
    echo "ANCHOR_NOT_FOUND" >&2
    if [[ -z "$SINCE" ]]; then
      local suggested_since
      suggested_since="$(suggest_manual_since "$SOURCE_ANALYSIS_FILE" "$email")"
      if [[ -n "$suggested_since" ]]; then
        echo "建议人工确认后使用 --since $(short_sha "$suggested_since")；--since 会包含该 commit 本身。" >&2
      fi
      fail "未找到最近已搬运锚点（已限制搜索$(recent_window_hint)）。请使用 --since <commit> 手动指定起始 commit"
    fi
    fail "未找到最近已搬运锚点，无法安全判断本次需要搬运的提交范围。可使用 --since <commit> 指定起始点"
  fi
  source_anchor="${anchor_pair%% *}"
  target_anchor="${anchor_pair##* }"

  collect_commits "$source" "$email" "$COMMITS_FILE" "$PRESENT_FILE" "$NON_USER_FILE" "$MERGE_FILE" "$source_anchor" "$([[ "$target_anchor" == "<manual>" ]] && echo true || echo false)" "$SOURCE_ANALYSIS_FILE"
  if [[ "$target_anchor" != "<manual>" ]]; then
    collect_pre_anchor_commits "$email" "$source_anchor" "$PRE_ANCHOR_FILE" "$SOURCE_ANALYSIS_FILE"
  fi
  print_plan "run" "$TARGET" "$source" "$base_ref" "$COMMITS_FILE" "$PRESENT_FILE" "$NON_USER_FILE" "$MERGE_FILE" "$source_anchor" "$target_anchor" "$PRE_ANCHOR_FILE" "$PREFLIGHT_STOPPED_FILE"

  if [[ ! -s "$COMMITS_FILE" ]]; then
    echo
    echo "没有需要 cherry-pick 的提交。"
    echo "当前工作区未切换分支: $source"
    return
  fi

  prepare_run_worktree "$base_ref"
  local total index sha
  total="$(line_count "$COMMITS_FILE")"
  index=0
  SUCCESS_FILE="$(mktemp)"
  trap 'rm -f "$COMMITS_FILE" "$PRESENT_FILE" "$NON_USER_FILE" "$MERGE_FILE" "$PRE_ANCHOR_FILE" "$PREFLIGHT_STOPPED_FILE" "$SOURCE_META_FILE" "$PATCH_STATE_FILE" "$SOURCE_ANALYSIS_FILE" "$SUCCESS_FILE"; cleanup_run_worktree' EXIT

  while read -r sha; do
    [[ -n "$sha" ]] || continue
    index=$((index + 1))
    echo
    echo "[$index/$total] cherry-pick $(short_sha "$sha") $(commit_subject "$sha")"
    if git -C "$RUN_WORKTREE" cherry-pick "$sha"; then
      echo "$sha" >>"$SUCCESS_FILE"
      continue
    fi

    echo >&2
    echo "CHERRY_PICK_STOPPED" >&2
    echo "冲突现场目录: $RUN_WORKTREE" >&2
    echo "当前 commit: $(short_sha "$sha") $(commit_subject "$sha")" >&2
    echo "已成功: $(line_count "$SUCCESS_FILE")" >&2
    if [[ -s "$SUCCESS_FILE" ]]; then
      echo "已成功提交:" >&2
      printf '  %s %s %s %s\n' "#" "提交" "时间" "说明" >&2
      local done_index=0 done_sha
      while read -r done_sha; do
        [[ -n "$done_sha" ]] || continue
        done_index=$((done_index + 1))
        printf '  %s %s %s\n' "$done_index" "$(short_sha "$done_sha")" "$(commit_time "$done_sha")" >&2
        printf '    说明: %s\n' "$(commit_subject "$done_sha")" >&2
      done <"$SUCCESS_FILE"
    fi
    echo "剩余未执行:" >&2
    awk -v current="$sha" 'BEGIN{seen=0} $0==current{seen=1; next} seen{print}' "$COMMITS_FILE" | while read -r left_sha; do
      [[ -n "$left_sha" ]] || continue
      printf '  - %s %s\n' "$(short_sha "$left_sha")" "$(commit_time "$left_sha")" >&2
      printf '    说明: %s\n' "$(commit_subject "$left_sha")" >&2
    done
    cat >&2 <<'EOF'
请人工判断后执行：
  git cherry-pick --continue
或：
  git cherry-pick --skip
或：
  git cherry-pick --abort
EOF
    exit 4
  done <"$COMMITS_FILE"

  local new_head
  new_head="$(git -C "$RUN_WORKTREE" rev-parse HEAD)"
  update_local_target_branch "$TARGET" "$new_head"

  if [[ "$PUSH" == true ]]; then
    push_run_worktree_head "$TARGET"
  fi

  cleanup_run_worktree
  echo
  echo "完成。当前工作区未切换分支: $source"
}

main() {
  parse_args "$@"
  git rev-parse --git-dir >/dev/null 2>&1 || fail "当前目录不是 Git 仓库"
  case "$MODE" in
    plan) run_plan ;;
    run) run_execute ;;
  esac
}

main "$@"
