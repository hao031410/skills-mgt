# 错误处理与降级策略（requirement-analyzer 内部参考）

> 定义 requirement-analyzer 在各种异常场景下的处理策略。

---

## 降级矩阵

| 场景 | 级别 | 处理方式 | 用户提示 |
|------|------|---------|---------|
| meegle 未认证 | 🔴 阻断 | 中断工作流 | "meegle 未登录，请先执行 meegle auth login" |
| 所有迭代返回 0 条需求 | 🔴 阻断 | 中断工作流 | "未找到匹配迭代 <名称> 的需求，请核实迭代名称是否正确" |
| 所有分析 Agent 失败 | 🔴 阻断 | 中断工作流 | "所有需求分析均失败，请检查产品线映射和仓库状态" |
| 部分迭代返回 0 条需求 | 🟡 警告 | 跳过空迭代，继续其他迭代 | "迭代 <名称> 未找到需求，已跳过" |
| 产品线无映射 | 🟡 警告 | 提示用户，跳过无映射需求 | "产品线 <名称> 未在映射表中，请确认仓库路径或更新 product-line-mapping.md" |
| codebase-memory 索引缺失 | 🟡 警告 | 降级为 grep/Glob 搜索，分析文档中标注 | "codebase-memory 索引不可用，使用文本搜索替代（可能不完整）" |
| 单个 wiki URL 不可访问 | 🟡 警告 | 记录原因，仅用 description 继续 | "wiki <URL> 不可访问（<原因>），使用需求描述文本作为输入" |
| 单个分析 Agent 失败 | 🟡 警告 | 标记该需求为"分析失败"，继续其余需求 | "需求 <标题> 分析失败：<原因>" |
| 审核 Agent 失败 | 🔵 信息 | 文档保留，标注"未经审核" | "审核 Agent 执行失败，输出文档未经审核，请人工检查" |

---

## 常见错误与处理

### 1. meegle 认证失败

**症状**：调用 meegle skill 返回认证错误

**处理**：
```
⚠️ meegle 认证失败。请执行以下命令后重试：
  meegle auth login
```

### 2. 迭代名称不匹配

**症状**：客户端过滤后 0 条需求匹配

**原因**：
- 迭代名称拼写错误（大小写、日期格式）
- `planning_sprint[].label` 中迭代名与用户输入不匹配
- story 未规划到该迭代

**处理**：
```
⚠️ 迭代 "<名称>" 未匹配到任何需求。可能的原因：
1. 迭代名称拼写错误，当前已拉取的迭代列表：
   - <列出现有的 planning_sprint label>
2. 用户在此迭代中没有参与的需求
3. 需求尚未规划到该迭代

建议：核实迭代名称或尝试其他查询条件。
```

### 3. 产品线映射缺失

**症状**：迭代前缀不在 `product-line-mapping.md` 的映射表中

**处理**：
```
⚠️ 无法从迭代名称 "<名称>" 中识别产品线。
已知产品线：FSMS（食品安全管理系统）
请指定产品线名称或仓库路径，或在 references/product-line-mapping.md 中添加映射。
```

### 4. Git 仓库不存在

**症状**：映射表中的仓库路径不存在或无 `.git/` 目录

**处理**：
```
⚠️ 产品线 <名称> 的仓库路径 <路径> 不存在或不是 Git 仓库。
请确认：
1. 仓库已 clone 到正确位置
2. product-line-mapping.md 中的路径正确
```

### 5. wiki 文档过大导致超时

**症状**：lark-wiki/lark-doc 读取超时或响应过大

**处理**：保存已读取的部分到 `_raw/wiki_<token>_PARTIAL.md`，标注截断位置。分析 Agent 使用已获取的内容继续分析。

### 6. 分析 Agent 超时或崩溃

**症状**：子 Agent 超过执行时间限制或返回错误

**处理**：
- 该需求标记为"分析失败"
- 在 SUMMARY.md 中明确标注失败原因
- 用户可手动重试该需求

### 7. git log -G 返回空但代码中有相关逻辑

**症状**：代码中存在相关实现但 git log -G 搜索无命中

**可能原因**：
- 搜索的关键词与代码中的实际用词不匹配
- 代码是历史遗留（非本迭代引入）
- commit 被 squash/rebase 导致历史丢失

**处理**：以"当前代码状态"为准判定。如果代码中确实有实现但 git log 找不到相关 commit，标 PARTIAL 并注明"有实现但无法追溯到具体 commit"。

### 8. MQL 查询报 `attr label not found`（字段名错误）

**症状**：meegle MQL 查询返回 `attr label not found` 或 `attribute key or value error`

**根因**：MQL 中的字段 key 与 meegle schema 不一致。常见错误：
- 用了 `status` 而非 `work_item_status`
- 用了 `update_time` 而非 `updated_at`
- 用了 `create_time` 而非 `start_time`

**预防**：执行 MQL 前先跑一次 `meegle workitem meta-fields --work-item-type story --project-key xlb --page-num 1` 确认字段 key。

**处理**：根据 `meta-fields` 返回的 `field_key` 修正 MQL 后再执行。

### 9. `meta-fields` 报 `required flag(s) "page-num" not set`

**症状**：调用 `meegle workitem meta-fields` 时报缺少 `--page-num` 参数

**处理**：meta-fields 命令**必须**带 `--page-num 1`（该参数是必填的，不是可选的）。字段量大时翻页取全量。

---

## 重试指南

requirement-analyzer **不自动重试**。如果用户需要对失败的需求重新分析：

1. 用户手动指定失败的需求名称
2. 重新执行 skill，skill 会重新从飞书拉取
3. 或者用户指定 `--from-snapshot <yyMMdd-slug>` 复用已有的 `_raw/` 快照避免重复拉取
