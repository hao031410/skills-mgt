# feishu 工具集成（work-report skill 内部参考）

> 吸收自 vanchen 聚合根 `docs/feishu.md` 的 meegle / lark-cli 使用经验，凝练为 LLM 行动指引。
> 与原文档的关系：原文档是团队完整沉淀（包含 IM/Sheet/Base 等场景）；本文只覆盖 work-report 所需的最小集。
> 详细踩坑与备选命令如有疑问，回到 `docs/feishu.md` 查证。

---

## 1. 认证前置

**每个 work-report 任务开始前**：

1. 调 meegle skill 的认证状态命令（见 meegle skill SKILL.md 的 `Auth` 域）确认登录态
2. 未登录：**中断工作流**，提示用户执行 meegle skill 的登录命令
3. 不要替用户做 OAuth；这是用户主动行为

---

## 2. 默认配置（work-report 适用）

| 项 | 默认值 | 备注 |
|---|---|---|
| 当前登录用户 | 居士浩（`user_key=7651648813123374258`） | 通过 `current_login_user()` 在 MQL 中引用 |
| 默认 meegle 空间 | xlb（`project_key=65eef07569082b29c300cc80`，`simple_name=xlb`） | 用 `xlb` 或 `65eef07569082b29c300cc80` 都可 |
| 默认工作项类型 | `story`（中文名"研发需求"） | MQL `FROM` 中用 key `story`；中文名"研发需求"也可 |
| 迭代工作项类型 | `sprint` | 反查迭代用 `meegle workitem query ... FROM ... sprint` |

工作项类型 key 速查（xlb 空间常用）：

- `story`：研发需求（最常用）
- `issue`：缺陷
- `sub_task`：子任务
- `sprint`：迭代
- `version`：版本

---

## 3. 必读踩坑清单

执行 work-report 时**必须规避**的常见错误：

### 3.1 MQL 字段名必须用 key，不能用中文名

```sql
-- ❌ 报 "attr label not found"
SELECT `工作项ID` FROM `xlb`.`story`

-- ✅
SELECT `work_item_id` FROM `xlb`.`story`
```

### 3.2 `planning_sprint` 不能在 MQL 中按 label/key 过滤

`planning_sprint` 的值是 `{key, label}` 结构体数组（如 `[{key: "FSMS-20260727", label: "FSMS-20260727"}]`），所以：

- `array_contains(\`planning_sprint\`, 'FSMS-20260727')` → **返回空**（值是结构体不是字符串）
- `array_contains(\`planning_sprint\`, '6994227306')` → **报错** `attrValueLabel not found`

**正确做法**：

1. 先全量拉"我参与的"story（带 `planning_sprint` 字段）
2. 在客户端读 `planning_sprint[].label` 做时间窗口+迭代过滤

### 3.3 description 字段是字符串，可能含 wiki URL

- meegle workitem 拉到的 description 字段是**纯字符串**（不是 `{text, type}` 嵌套对象）
- 内部通常是 Markdown + 富文本嵌入，可能含两类 URL：
  - `https://<tenant>.feishu.cn/wiki/<token>?from=...` → 知识库节点
  - `https://project.feishu.cn/goapi/v5/platform/file/stream/download/<signed>` → 附件下载（不是文本）
- work-report **不需要**读 description 正文，**不需要**抓 wiki URL
- 如果归并阶段 commit message 含描述性关键字但需要上下文，可选择性拉 description 做参考（不是必须）

### 3.4 `meegle workitem meta-fields` 必须带 `--page-num`

否则报 `required flag(s) "page-num" not set`。

### 3.5 MQL `LIKE` 必须前后加 `%`

`FSMS-202%` 会报 `should like %T%`，必须写成 `%FSMS-202%`。

### 3.6 项目标志位置

`--project-key` 必须放在 `meegle workitem` 域级，不能放在 `+batch-get` / `+fetch` 之后（`+query` 是例外，两种位置都接受）：

```bash
# ❌ unknown flag
meegle workitem +batch-get --project-key=xxx --work-item-ids ...

# ✅
meegle workitem --project-key=xxx +batch-get --work-item-ids ...
```

### 3.7 lark-cli skills 版本不同步

- 告警（`current: 1.0.55, target: 1.0.65`）**不会**让命令失败，可以忽略
- 写脚本时如要稳定 JSON，可前置 `LARKSUITE_CLI_NO_UPDATE_NOTIFIER=1 LARKSUITE_CLI_NO_SKILLS_NOTIFIER=1`
- work-report 不写脚本，忽略此点

---

## 4. 角色 / 参与人员 MQL 函数

| 语义 | MQL 语法 | 适用场景 |
|---|---|---|
| 我参与的（全部角色） | `array_contains(all_participate_persons(), current_login_user())` | work-report 默认用这个，覆盖所有角色 + 关注人 + 节点负责人 |
| 我负责的（按角色） | `array_contains(\`__RD\`, current_login_user())` | 需先 `meegle workitem meta-roles` 拿角色名 |
| 当前登录用户引用 | `current_login_user()` | MQL 内置函数 |

`current_login_user()` 直接在 MQL 内用，不需要先查 user_key。

---

## 5. work-report 标准查询路径（4 步）

### 步骤 A：MQL 拉"我参与的"story 列表

用 meegle skill 的工作项查询能力，参考 `references/meegle-queries.md` 的模板。

- 选 `story` 工作项类型
- 范围：`array_contains(all_participate_persons(), current_login_user())`
- 拉满 `LIMIT 50`（**不要只拉 1-2 条**；description 命中率约 4/11，需要量保证）
- 选字段：`work_item_id`, `name`, `status`, `priority`, `current_status_operator`, `watchers`, `description`, `planning_sprint`, `update_time`

### 步骤 B：客户端按时间窗口 + 迭代过滤

- 在内存中过滤 `update_time` 在 `[from, to]` 范围内
- 如果用户指定了迭代（如"FSMS-20260727"），过滤 `planning_sprint[].label` 包含该迭代

### 步骤 C：（可选）补 description / planning_sprint 字段

如步骤 A 返回的字段不全，用 meegle skill 的 `+batch-get` 补充：

```bash
meegle workitem --project-key=xlb +batch-get \
  --work-item-ids "<id1>,<id2>,..." \
  --fields description,planning_sprint \
  --format json
```

### 步骤 D：归并进 work-report 中间产物

每条 story 转为：

```yaml
- key: "story#<work_item_id>"
  title: "<name>"
  status: "<status>"          # 用于 section 判定
  raw_story: {...}            # 原始 payload
```

---

## 6. work-report 不做的事

- ❌ **不读 description 正文**：work-report 只用 status/name 归类，不读需求正文
- ❌ **不抓 wiki URL**：同上
- ❌ **不读 description 中的图片/附件**：超出 work-report 范围
- ❌ **不写 lark-IM/Sheet/Base 等命令**：work-report 只需要 meegle + git
- ❌ **不调用 lark-cli docs**：除非用户在工作流中明确要求读某条需求的正文
- ❌ **不调用 lark-task**：当前需求未涉及飞书任务；如未来需要扩展，见 SKILL.md "预留扩展位" 章节
- ❌ **不创建/更新飞书工作项**：work-report 是只读工作流
- ❌ **不实现 lark-cli version update**：忽略告警即可
