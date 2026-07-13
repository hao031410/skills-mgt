# meegle 标准 MQL 模板（work-report skill 内部参考）

> work-report 在 Step 2（拉取飞书需求）阶段使用的 MQL 模板。
> 实际命令通过 meegle skill 调用，**不在本 skill 中硬编码具体 CLI 语法**。
> 本文档只描述**查询语义**，具体调用方式由 LLM 调 meegle skill 自适应。

---

## 1. 默认查询（work-report 主体使用）

### 1.1 拉"我参与的"story 列表

**目的**：拿到 work-report 用户作为参与人（任意角色）的全部研发需求。

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
  `update_time`
FROM `65eef07569082b29c300cc80`.`story`
WHERE array_contains(all_participate_persons(), current_login_user())
ORDER BY `update_time` DESC
LIMIT 50
```

**关键点**：

- `FROM` 中工作项类型用 key `story`（不用中文名"研发需求"）
- 字段名全部用 key（`work_item_id` 而非"工作项ID"）
- `LIMIT 50` 是 meegle 默认每页上限；超 50 条需翻页
- 时间窗口过滤在**客户端**做（见 `references/feishu-integration.md` §3.2）
- 拉满一页再客户端过滤，**不要**只拉 1-2 条

### 1.2 客户端过滤规则

拿到 §1.1 结果后，在内存中过滤：

```python
filtered = [
    story for story in fetched
    if is_in_window(story.update_time, window_from, window_to)
    and (not sprint_label or has_sprint(story.planning_sprint, sprint_label))
    and story.status not in ("已终止", "已取消")  # 默认排除
]
```

- `is_in_window`：判断 `update_time` 是否在 `[from, to]` 范围内
- `has_sprint`：读 `planning_sprint[].label`，判断是否包含目标迭代
- 状态过滤：默认排除"已终止/已取消"，其他状态全部进入 work-report 中间产物（用于 4 段判定）

### 1.3 补字段（仅当 §1.1 返回字段不全时）

如 meegle skill 的 list query 返回不包含 `description` 或 `planning_sprint`，用 meegle skill 的 `+batch-get` 补取：

```bash
meegle workitem --project-key=xlb +batch-get \
  --work-item-ids "<id1>,<id2>,<id3>" \
  --fields description,planning_sprint \
  --format json
```

**注意**：`--project-key` 必须放在 `meegle workitem` 域级（见 `references/feishu-integration.md` §3.6）。

---

## 2. 备选查询（按需使用）

### 2.1 按迭代名查全部需求（不限参与角色）

适用：当用户明确说"整理 FSMS-20260727 整个迭代的工作"，需要看所有需求而非只"我参与的"。

```sql
SELECT
  `work_item_id`,
  `name`,
  `status`,
  `priority`,
  `current_status_operator`
FROM `65eef07569082b29c300cc80`.`story`
WHERE array_contains(`planning_sprint`, 'FSMS-20260727')
ORDER BY `update_time` DESC
LIMIT 50
```

⚠️ `planning_sprint` 在 MQL 中**可按**结构体**匹配**（不是过滤 `label`）——这里用的是结构体匹配，不是字符串包含。

### 2.2 反查迭代本身（拿 sprint key）

```sql
SELECT `work_item_id`, `name`
FROM `65eef07569082b29c300cc80`.`sprint`
WHERE `name` IN ('FSMS-20260727', 'FSMS-20260713')
```

仅在需要"迭代 → 需求"的反向回查时使用。

### 2.3 我负责的（按角色，如 RD/QA/PM）

```sql
-- "我作为 RD 负责的"（角色名 `__RD` 是 xlb 空间的常见名）
SELECT `work_item_id`, `name`, `status`
FROM `65eef07569082b29c300cc80`.`story`
WHERE array_contains(`__RD`, current_login_user())
```

角色名通过 meegle skill 的 `meta-roles` 命令动态拿（不要硬编码 `__RD`）。

### 2.4 按 work_item_id 直查单条

适用：归并阶段如果 commit message 含 `#1234` 想拿该 story 详情。

```bash
meegle workitem --project-key=xlb get --work-item-id 1234
```

或用 `+batch-get --work-item-ids 1234`。

---

## 3. 字段说明

### 3.1 必选字段（work-report 必须）

| 字段 | 用途 |
|---|---|
| `work_item_id` | 中间产物 `key: "story#<id>"` |
| `name` | 中间产物 `title` |
| `status` | 4 段归类判定（见 `references/status-mapping.md`） |
| `update_time` | 时间窗口过滤 |

### 3.2 推荐字段

| 字段 | 用途 |
|---|---|
| `priority` | 报告头部摘要（高优需求标注） |
| `current_status_operator` | 报告脚注"当前负责人" |
| `planning_sprint` | 客户端按迭代过滤 |
| `description` | 仅在归并阶段需要上下文时拉取 |

### 3.3 可选字段

| 字段 | 用途 |
|---|---|
| `watchers` | 报告脚注"关注人" |
| `create_time` / `due_date` | 报告脚注"创建/截止时间" |

---

## 4. 分页策略

meegle 默认每页 50 条：

- 第一页：`--page-num 1`（或默认）
- 后续页：循环 `--page-num 2`, `3`, ... 直到返回空数组
- 替代方案：用返回的 `session_id` + `--group-pagination-list` 翻页（适用于大批量）

work-report 默认场景（一人一周/一月）通常不会超过 50 条，但 LLM 需判断是否需要翻页。

---

## 5. 客户端数据规范化

meegle 返回的字段值格式（STRING 协议）：

- 所有 `field_value` 都是字符串
- 数组/对象需在 meegle 协议层用 `JSON.stringify` 编码（这是 meegle CLI 行为，LLM 不需要关心）
- multi-user 字段（如 `current_status_operator`）值是 `["userkey1", "userkey2"]` 字符串

work-report 只需：

- 直接读 `field_value` 字符串
- 数组/对象字段（如 `planning_sprint`）按 JSON 解析即可

---

## 6. work-report 用的 MQL 函数速查

| 函数 | 用途 |
|---|---|
| `current_login_user()` | 当前登录用户（work-report 用户的 meegle 身份） |
| `all_participate_persons()` | 需求的所有参与人（产品+RD+QA+PM+关注人+节点负责人） |
| `array_contains(field, value)` | 数组包含判断（MQL 通用） |
| `LIKE '%...%'` | 模糊匹配（必须前后都有 `%`） |

---

## 7. 不要做的事

- ❌ **不写 MQL 以外的命令**：meegle 增删改不在 work-report 范围
- ❌ **不查询非 story 工作项类型**：issue/sub_task 当前不需要（除非未来扩展）
- ❌ **不预先过滤掉"未开始"状态**：未开始 story 可能含"下周计划"信息，留给 §1.2 后的 4 段判定处理
- ❌ **不解析 description 中的 wiki URL**：work-report 不读需求正文
- ❌ **不创建/更新工作项**：work-report 是只读工作流
