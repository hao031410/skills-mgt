---
name: work-report
description: 根据指定时间窗口生成工作报告。默认从飞书项目 (meegle) + 本仓库及子项目 git log 拉取工作内容，按飞书需求项归并，输出 4 段（已完成/进行中/存在问题/下周计划）报告。适用于生成周报/日报/月报/任意起止时间报告。当用户输入 "/work-report" 或表达"生成本周周报"/"整理 7.1-7.12 的工作报告"/"出个月报"等需求时触发。
---

# work-report skill

## 触发

用户表达包括但不限于：

- `/work-report`（直接调用）
- `/work-report --type weekly` / `--type daily` / `--type monthly` / `--type custom`
- `/work-report --from 2026-07-01 --to 2026-07-12`（任意起止）
- "生成本周周报" / "整理上周工作" / "出个月报" / "帮我做个日报" / "7.1 到 7.12 的工作报告"

## 工作流（6 步）

### Step 1: 收集时间窗口与配置

**默认行为**：

- 默认报告类型 = `weekly`（本周）
- 本周窗口 = 本周一 00:00 ~ 今天 23:59
- 默认用户邮箱 = `git config --global user.email` 输出
- 默认 meegle 空间 = `xlb`（`project_key=65eef07569082b29c300cc80`）

**用户可指定**：

| 参数 | 取值 | 说明 |
|---|---|---|
| `--type` | `daily` \| `weekly` \| `monthly` \| `custom` | 默认 `weekly` |
| `--from` | `YYYY-MM-DD` | `--type=custom` 时必填 |
| `--to` | `YYYY-MM-DD` | `--type=custom` 时必填 |
| `--user` | 邮箱字符串 | 覆盖 git config 推断 |
| `--meegle-project` | 空间 simple_name | 默认 `xlb` |
| `--output` | 路径 | 默认 `docs/reports/<type>-<from>-<to>.md` |

如果用户没有给出明确时间窗口，使用本周；用户主动给的优先级最高（自然语言里的"上周"/"7.1-7.12"等需解析为 ISO 日期）。

### Step 2: 拉取飞书需求（走 meegle skill）

调 meegle skill 工作项域命令，MQL 模板和已知坑见 `references/meegle-queries.md` 与 `references/feishu-integration.md`。

**核心要求**：

1. **先调 meegle auth status 确认认证**：未登录则中断并提示用户先 `meegle auth login`
2. **拉取范围**：用 meegle skill 的工作项查询能力拉"我参与的 story"（不限状态），具体 MQL 见 `references/meegle-queries.md`
3. **客户端过滤迭代**：`planning_sprint` 字段值是 `{key, label}` 结构体数组，MQL 无法直接过滤，必须在拿到结果后读 `planning_sprint[].label` 在客户端做时间窗口+迭代的过滤
4. **必要时补 description / planning_sprint**：用 meegle skill 的 `+batch-get` 取补充字段
5. **保留原始 payload**：每条 story 的全部原始字段保留在中间产物 `raw` 中供归并使用

**如果 meegle 拉取失败**：在报告头部明确标注「飞书数据拉取失败：<原因>」，报告只含 git 数据，继续完成。

### Step 3: 拉取本地 git log

详细规范见 `references/git-conventions.md`。

**核心要求**：

1. **自动发现子项目**：从当前工作目录（vanchen 聚合根）递归扫描所有含 `.git/` 的目录
2. **每个 git 仓单独跑**：
   ```bash
   git -C <repo> log --since=<from> --until=<to+1> --author=<email> \
     --pretty=format:'%H|%ai|%an|%s' --no-merges
   ```
3. **多用户支持**：默认取 `git config --global user.email` 一个用户；用户可通过 `--user` 覆盖或 `WORK_REPORT_USERS` 环境变量（逗号分隔）指定多个
4. **commit message 解析**：兼容 `<emoji> <type>(<scope>): <subject>` 格式（本项目用 emoji 规范），提取 type/scope/subject
5. **对未匹配 commit 调用 `git show --stat <hash>`**：获取修改文件列表，供 LLM 兜底归并使用

**如果某子项目无 commit**：记录 0 commits，继续下一个，不报错。

### Step 4: 归并（commit → story）

详细算法见 `references/merge-strategy.md`。

**三阶段匹配**：

1. **阶段 1：显式 ID 匹配**：commit message 中正则 `\b#(\d{4,})\b` 或 `xlb-(\d+)` 提取 workitem id
2. **阶段 2：标题模糊匹配**：commit subject 前 10 词 vs story name 前 10 词的 Jaccard 相似度 ≥ 0.4
3. **阶段 3：LLM 智能兜底**：对仍未匹配的 commit（一次最多 10 条合并 prompt），取 commit message + `git show --stat` 修改文件列表，LLM 判断归到哪个 story 或 `null`
4. **仍未匹配 → key=`other:<n>`**：LLM 根据 commit 内容整理一个简洁的"需求主题"作为标题

**输出**：归并后的 `items` 列表，每条形如：
```yaml
- key: "story#1234" | "other:1"
  title: "..."            # 来自 story.name 或 LLM 整理
  section: "已完成工作" | "进行中工作"   # 详见 Step 5
  commits: [hash, ...]
  raw_story: {...}        # 飞书 story 原始 payload（可选）
  raw_commits: [...]      # git commit 原始 payload（可选）
```

### Step 5: 状态判定 + 推断

详细映射见 `references/status-mapping.md`。

**4 段归类规则**：

| 数据来源 | 字段/特征 | section |
|---|---|---|
| 飞书 story | status = 已完成 / 已关闭 | 已完成工作 |
| 飞书 story | status = 进行中 | 进行中工作 |
| 飞书 story | status = 未开始 | （不进入本期） |
| 飞书 story | status = 已终止 / 已取消 | （不进入本期） |
| 飞书 story | status = 已延期 / 风险 / 阻塞 | 触发"存在问题" |
| commit | type = fix / bug，且未关闭相关 story | 触发"存在问题" |
| commit | type = WIP / draft / subject 含 "partially" | 触发"下周计划" |
| other 项（未匹配） | 由 LLM 推断 section | 任意 |

**自动推断**：

- **下周计划** = 本期"进行中工作" + "WIP/draft/partially" commit（取 commit subject）
- **存在问题** = 已延期 story 列表 + fix/bug commit（取 commit subject）

### Step 6: 渲染输出

按 `assets/report-template.md` 填充。

**输出路径**：默认 `docs/reports/<type>-<from>-<to>.md`（如 `docs/reports/weekly-2026-07-06-2026-07-12.md`）

**写入前**：用 AskUserQuestion 或一句话确认：

> 报告将输出到 `docs/reports/<path>`，是否写入？

**渲染时**：

- 4 段按"已完成 → 进行中 → 存在问题 → 下周计划"固定顺序
- 每段下平铺需求项名称（不展开 commit 清单）
- 某段为空时显示"（本期无）"
- 头部包含：报告人 / 时间窗口 / 类型 / 数据源统计

## 中间产物（LLM 内存中维护）

不需要写入文件，LLM 在执行过程中维护：

```yaml
report:
  window: {from, to, type}
  user: {email, name}
  source_stats:
    meegle: {fetched: N, filtered: M, status: ok|failed}
    git: {repos: [...], commits: K, by_repo: {...}}
  items:
    - key: "story#1234" | "other:1"
      title: "..."
      section: "已完成工作|进行中工作"
      commits: [hash, ...]
  inferred:
    next_week_plan: [str, ...]
    issues: [str, ...]
```

## 错误处理（详见 references/troubleshooting.md）

| 情况 | 处理 |
|---|---|
| meegle 拉取失败 | 报告头部标注「飞书数据拉取失败：<原因>」，只用 git 数据继续 |
| 归并命中率 < 50% | 提示用户确认【其他】分类是否合理，可手动指定 |
| git 无 commit | 在报告头部标注「本期无 commit 工作」，只有飞书数据 |
| meegle 未登录 | 中断，提示用户 `meegle auth login` |
| 飞书 story 0 条 | 在报告头部标注「本期无飞书工作项」，只用 git 数据 |

## 不要做的事

- ❌ **不写 Python 脚本**（CLI 命令可能变化，硬编码会失效；meegle/lark-cli 后续命令格式变动时不需要改本 skill）
- ❌ **不调任何固定的 meegle/lark 子命令**（由 LLM 调 meegle skill 自适应最新接口）
- ❌ **不写单元测试**（无脚本可测；skill 的正确性靠人工 review 和实际运行验证）
- ❌ **不询问用户"下周计划/存在问题"**（纯自动推断）
- ❌ **不写"上周报告 → 下周计划"自动链接**（每期独立）
- ❌ **不实现 weekly-report 的 7 段模板**（严格 4 段）
- ❌ **不写报告归档管理**（输出由用户自行管理）
- ❌ **不强约束 CLI 命令格式**（不写 wrapper 脚本）

## 相关 references

- `references/feishu-integration.md` — 吸收自 `docs/feishu.md` 的 meegle/lark-cli 调用规范
- `references/meegle-queries.md` — 标准 MQL 模板
- `references/status-mapping.md` — meegle status → 报告 4 段映射
- `references/merge-strategy.md` — 三阶段 commit → story 归并算法
- `references/git-conventions.md` — commit 解析 + 子项目发现 + 用户过滤
- `references/troubleshooting.md` — 常见错误处理
- `assets/report-template.md` — 4 段 Markdown 报告模板
