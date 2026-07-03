---
name: git-auto-cp
description: 当需要将当前分支中当前 Git 用户的提交 cherry-pick 到目标测试或集成分支，且分支无法直接合并或用户调用 /git-auto-cp 时使用。
argument-hint: <target-branch> [-a] [-p] [--since <commit>]
---

# Git Auto Cp

## 概述

自动化执行安全的两阶段 cherry-pick 流程：将当前 Git 用户在当前源分支上的提交搬运到目标分支。优先使用随 skill 提供的脚本，不要临场手写 Git 命令；脚本已经固化确认过的安全规则。

## 命令

```text
/git-auto-cp <target-branch> [-a] [-p] [--since <commit>]
```

参数说明：

| 参数 | 含义 |
| --- | --- |
| `<target-branch>` | 必填，目标分支，例如 `test` 或 `release/test` |
| `-a` | 自动模式：跳过普通计划确认；若当前仓库有未提交变更，先自动 commit 再继续 |
| `-p` | 所有 cherry-pick 成功后，将目标分支 push 到其 upstream |
| `--since <commit>` | 手动指定起始 commit（包含该 commit 本身及其之后的提交将被 cherry-pick） |

`-p` 不隐含 `-a`。`-a` 永远不能跳过“非 feature 源分支”的危险确认。

## 工作流

使用随 skill 提供的脚本：

```bash
.claude/skills/git-auto-cp/scripts/git_auto_cp.sh plan <target-branch> [-p] [--since <commit>]
.claude/skills/git-auto-cp/scripts/git_auto_cp.sh run  <target-branch> [-p] [--since <commit>]
```

执行前先检查当前仓库是否存在未提交变更：

1. 先判断当前源分支是否为 `feature` 开头；若不是，即使带 `-a` 且工作区不干净，也必须先停止并要求用户明确确认，不能先自动 commit。
2. 若工作区干净，继续正常流程。
3. 若工作区不干净且未带 `-a`，先提示用户：是否先自动 commit 当前变更，再继续 cherry-pick。
4. 若工作区不干净且带 `-a`，只有在源分支已确认安全后，才可以先自动 commit，再继续后续流程。

自动 commit 策略：

1. 优先使用 `git-commit` skill。
2. 如果当前环境没有 `git-commit` skill，则使用 agent 自身的自动提交策略生成 commit。
3. commit message 按当前变更内容自动生成；不要写死固定文案。
4. 自动 commit 完成后，再执行下面的 `plan` 或 `run` 流程。

默认半自动流程：

1. 如有未提交变更，先询问用户是否自动 commit；用户确认后先完成 commit。
2. 执行 `plan`。
3. 向用户展示计划：源分支、目标分支、作者邮箱、过滤后的提交列表、被跳过的统计信息。
4. 请求用户确认。
5. 只有在用户确认后，才执行 `run`。

带 `-a` 的自动流程：

1. 如有未提交变更，先自动 commit。
2. 直接执行 `run`。
3. 如果脚本输出 `NON_FEATURE_SOURCE_CONFIRM_REQUIRED`，立即停止，并请求用户明确确认；确认后再追加 `--allow-non-feature-source` 重试。
4. 如果脚本输出 `ANCHOR_NOT_FOUND`，立即停止；即使带 `-a` 也不能自动猜测起点，必须由用户人工确认后使用 `--since <commit>`。

无论哪种模式，只要源分支不是 `feature` 开头，都不能静默继续。用户确认后，在同一个 `plan` 或 `run` 命令后追加 `--allow-non-feature-source`。

## 脚本规则

脚本强制执行以下规则：

- 真正调用脚本前，必须保证工作区干净；绝不自动 stash。
- `plan` 可以执行 `git fetch origin --prune`，但绝不切分支、pull、cherry-pick、push 或 stash。
- `run` 必须重新计算所有信息；绝不信任之前的 plan 缓存。
- 目标分支必须是本地已有 upstream 的分支，或存在 `origin/<target>`；绝不创建全新的目标分支。
- 如果本地目标分支存在且有 upstream，比较基准是 upstream（例如 `origin/test`），不是本地落后的 `test`；计划中必须展示本地目标分支、比较基准以及 ahead/behind。
- 未指定 `--since` 时，只分析源分支最近7天的 first-parent 提交；超过该窗口的历史不自动扫描，避免大历史拖慢执行。
- 锚点定位策略（按优先级）：
  1. 如果指定了 `--since <commit>`，跳过自动锚点查找，直接从该 commit 开始收集候选提交，且包含该 commit 本身。
  2. 否则，在最近7天窗口内对目标分支所有可达提交与源分支做 patch-id 对比；源分支仍只分析 first-parent 链，从新到旧查找第一个已存在等价补丁且属于当前作者的非 merge 提交，作为锚点。
  3. 如果 patch-id 未匹配，再用同 author email、同 author date、同 commit subject 的目标分支最近窗口内所有可达提交作为保守兜底锚点，用于覆盖目标分支上下文不同导致 patch-id 不等价的已搬运提交。
  4. 如果找不到锚点且未指定 `--since`，立即停止，并提示用户使用 `--since` 手动指定；不要回退到全量扫描。
- 自动锚点模式只分析源分支上锚点之后的 first-parent 提交；手动 `--since` 模式从指定提交本身开始分析。
- 自动锚点模式如果发现锚点之前仍有当前用户的 `+` 提交，必须展示为“锚点前未搬运提交（不会自动 cherry-pick）”，帮助用户识别历史缺口，但不要自动回头搬运。
- 候选提交只在分析窗口内做 patch-id 去重，再按以下条件过滤：
  - 补丁尚未存在于目标分支（`git cherry` 输出 `+`）；
  - author email 精确等于 `git config user.email`；
  - 只处理普通提交；merge commit 会被跳过并展示；
  - 只考虑源分支 first-parent 历史上的提交。
- 按从旧到新的顺序 cherry-pick 提交。
- `plan` 阶段应在临时 worktree 中按顺序预检候选提交是否会停止（冲突或 empty cherry-pick），只报告风险并清理临时 worktree，不修改当前工作区或目标分支。
- `run` 在临时 `git worktree` 中执行 cherry-pick；当前工作区不切换分支。
- 如果发生冲突或 empty cherry-pick，立即停止，保留临时 worktree 里的 Git 现场，不 push，也不影响当前工作区。
- 全部成功后，可选地只向已有 upstream 执行 `git push`，并更新本地目标分支引用；当前工作区保持在原分支。
- 如果没有符合条件的提交，不执行 cherry-pick；`run` 中当前工作区保持不变。

## 结果处理

脚本成功时，报告目标分支、搬运的提交数量、是否 push，以及已经切回原源分支。

脚本以 `CHERRY_PICK_STOPPED` 停止时，告知用户：仓库被有意保留在目标分支，并展示脚本建议的命令：

```bash
git cherry-pick --continue
git cherry-pick --skip
git cherry-pick --abort
```

脚本报告没有符合条件的提交时，根据输出的统计信息解释原因：目标分支已存在等价补丁、非当前用户提交、被跳过的 merge commit。

脚本以 `ANCHOR_NOT_FOUND` 停止时，告知用户：无法自动定位锚点，建议使用 `--since <commit>` 手动指定起始 commit；`--since` 会包含该 commit 本身。

脚本在 `ANCHOR_NOT_FOUND` 时如果能识别最近窗口内最早的当前用户未搬运提交，可以输出一个建议的 `--since` 起点；该建议只用于人工确认，不能在 `-a` 下自动执行。

脚本以“工作区不干净”停止时，说明当前 skill 的预期前置动作没有完成：未带 `-a` 时应先询问是否自动 commit；带 `-a` 时应先自动 commit，再重试脚本。

如果工作区不干净且包含未跟踪文件或目录（例如 `.DS_Store`、`.codebase-memory/`、工具缓存目录），将其视为高风险自动 commit 内容；列出这些路径并让用户明确确认，不要静默纳入提交。

## 常见错误

| 错误做法 | 正确做法 |
| --- | --- |
| 使用 `prod` 作为 diff 基准 | 先定位最近已搬运锚点，只分析锚点之后的源分支提交 |
| 只按 SHA 判断提交是否存在 | 锚点优先用 `git cherry` patch-id，必要时用 author email/date/subject 兜底；候选用 `git cherry` 去重 |
| 把其他作者的提交也带过去 | 按 `author.email == git config user.email` 过滤 |
| 自动跳过冲突或 empty commit | 停止并保留 cherry-pick 现场 |
| 使用 `git push -u origin <target>` | 只 push 到已有 upstream |
| 从 `master`、`prod` 或 `test` 静默执行 | 要求用户明确确认非 feature 源分支 |
| 默认搜索全历史找锚点 | 默认限制最近7天范围，超出窗口提示 `--since` |
