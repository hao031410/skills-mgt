# meegle 标准 MQL 模板（requirement-analyzer skill 内部参考）

> requirement-analyzer 在 Step 2（拉取飞书需求）阶段使用的 MQL 模板。
> 从 work-report skill 的 `references/meegle-queries.md` 适配而成。
> 实际命令通过 meegle skill 调用，**不硬编码具体 CLI 语法**。

---

## 1. 主查询：按迭代拉取需求

### 1.1 拉取"我参与的"story 列表（默认）

**目的**：拿到当前用户作为参与人的全部研发需求，再客户端按迭代过滤。

```sql
SELECT
  `work_item_id`,
  `name`,
  `status`,
  `priority`,
  `current_status_operator`,
  `watchers`,
  `description`,
  `planning_sprint`,
  `update_time`,
  `create_time`
FROM `65eef07569082b29c300cc80`.`story`
WHERE array_contains(all_participate_persons(), current_login_user())
ORDER BY `update_time` DESC
LIMIT 50
```

**关键点**：
- `FROM` 中工作项类型用 key `story`（不用中文名"研发需求"）
- 字段名全部用 key（`work_item_id` 而非"工作项ID"）
- `LIMIT 50` 是 meegle 默认每页上限；超 50 条需翻页
- `planning_sprint` 在 MQL 中无法直接按 label/key 过滤（值是结构体数组 `[{key, label}]`），必须在客户端做

### 1.2 客户端过滤规则

拿到 §1.1 结果后，在内存中过滤：

```
filtered = [
    story for story in fetched
    if matches_iteration(story.planning_sprint, target_iterations)
    and (not name_filter or name_contains(story.name, name_filter))
    and (not id_filter or story.work_item_id in id_filter)
]
```

- `matches_iteration`：读 `planning_sprint[].label`，判断是否包含任一目标迭代名称
- `target_iterations`：用户在 Step 1 指定的迭代名称列表（如 `["FSMS-20260727"]`）
- `name_filter`：用户可选的需求名称子串过滤
- `id_filter`：用户可选的 work_item_id 精确过滤
- **不排除任何状态**：所有状态的 story 都进入分析（需求分析中、开发中、已完成等都需要分析）

### 1.3 补字段（仅当 §1.1 返回字段不全时）

如 meegle skill 的 list query 返回不包含 `description` 或 `planning_sprint`，用 `+batch-get` 补取：

```bash
meegle workitem --project-key=xlb +batch-get \
  --work-item-ids "<id1>,<id2>,<id3>" \
  --fields description,planning_sprint \
  --format json
```

**注意**：`--project-key` 必须放在 `meegle workitem` 域级（见 `references/feishu-integration.md` §3.6）。

---

## 2. 备选查询

### 2.1 按迭代名查全部需求（不限参与角色）

适用：当用户需要看整个迭代的所有需求，而非只"我参与的"。

```sql
SELECT
  `work_item_id`,
  `name`,
  `status`,
  `priority`,
  `description`,
  `planning_sprint`,
  `update_time`
FROM `65eef07569082b29c300cc80`.`story`
ORDER BY `update_time` DESC
LIMIT 50
```

然后在客户端按 `planning_sprint[].label` 过滤目标迭代。

### 2.2 按需求名称搜索

适用：用户只提供了需求名称/关键词，没有迭代名称。

```sql
SELECT
  `work_item_id`,
  `name`,
  `status`,
  `priority`,
  `description`,
  `planning_sprint`,
  `update_time`
FROM `65eef07569082b29c300cc80`.`story`
WHERE `name` LIKE '%<keyword>%'
ORDER BY `update_time` DESC
LIMIT 20
```

**注意**：MQL `LIKE` 必须前后都有 `%`（`LIKE '%keyword%'`），否则报错 `should like %T%`。

### 2.3 按 work_item_id 直查单条

```bash
meegle workitem --project-key=xlb get --work-item-id <id>
```

或用 `+batch-get --work-item-ids <id>`。

---

## 3. 字段说明

| 字段 | 用途 | 必选 |
|------|------|------|
| `work_item_id` | 需求唯一标识，生成 story#id key | ✅ |
| `name` | 需求标题，作为分析文档标题 | ✅ |
| `status` | 飞书状态，写入分析文档元数据 | ✅ |
| `description` | 需求描述文本，**从中提取 wiki URL** 并作为分析子 Agent 的输入 | ✅ |
| `planning_sprint` | 迭代归属，**客户端过滤的核心字段** | ✅ |
| `priority` | 优先级标注 | 推荐 |
| `current_status_operator` | 当前负责人 | 推荐 |
| `update_time` | 最近更新时间 | 推荐 |
| `create_time` | 创建时间 | 可选 |
| `watchers` | 关注人 | 可选 |

**与 work-report 的关键区别**：requirement-analyzer **必须**拉取 `description` 字段，因为需要从中提取 wiki URL 并作为分析子 Agent 的输入。

---

## 4. 分页策略

meegle 默认每页 50 条：

- 第一页：默认
- 后续页：循环 `--page-num 2`, `3`, ... 直到返回空数组
- 一个迭代通常不超过 50 条 story，但 LLM 需判断是否需要翻页

---

## 5. MQL 函数速查

| 函数 | 用途 |
|------|------|
| `current_login_user()` | 当前登录用户 |
| `all_participate_persons()` | 需求的所有参与人 |
| `array_contains(field, value)` | 数组包含判断 |
| `LIKE '%...%'` | 模糊匹配（必须前后都有 `%`） |

---

## 6. 不要做的事

- ❌ **不预先过滤掉任何状态**：需求分析中、开发中、已完成都需要分析代码现状
- ❌ **不创建/更新工作项**：requirement-analyzer 是只读工作流
- ❌ **不查询非 story 工作项类型**：issue/sub_task 当前不需要
