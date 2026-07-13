# 飞书工具集成（requirement-analyzer skill 内部参考）

> 从 work-report skill 的 `references/feishu-integration.md` 适配而成。
> 增加 lark-doc/lark-wiki 读取规范（requirement-analyzer 需要读取需求 wiki 正文）。
> 详细踩坑如有疑问，回到 vanchen 聚合根 `docs/feishu.md` 查证。

---

## 1. 认证前置

**每个 requirement-analyzer 任务开始前**：

1. 调用 meegle skill 的认证状态命令确认登录态
2. 未登录：**中断工作流**，提示用户执行 meegle skill 的登录命令
3. 不要替用户做 OAuth

---

## 2. 默认配置

| 项 | 默认值 | 备注 |
|---|---|---|
| 默认 meegle 空间 | xlb（`project_key=65eef07569082b29c300cc80`，`simple_name=xlb`） | 用 `xlb` 或 `65eef07569082b29c300cc80` 都可 |
| 默认工作项类型 | `story` | MQL `FROM` 中用 key `story` |
| 迭代工作项类型 | `sprint` | 反查迭代用 |

---

## 3. 必读踩坑清单（与 work-report 共享）

### 3.1 MQL 字段名必须用 key，不能用中文名

```sql
-- ❌ 报 "attr label not found"
SELECT `工作项ID` FROM `xlb`.`story`

-- ✅
SELECT `work_item_id` FROM `xlb`.`story`
```

### 3.2 `planning_sprint` 不能在 MQL 中按 label/key 过滤

`planning_sprint` 的值是 `{key, label}` 结构体数组，所以：

- `array_contains(\`planning_sprint\`, 'FSMS-20260727')` → **返回空**（值是结构体不是字符串）

**正确做法**：先全量拉 story（带 `planning_sprint` 字段），在客户端读 `planning_sprint[].label` 做迭代过滤。

### 3.3 MQL `LIKE` 必须前后加 `%`

`LIKE 'FSMS-202%'` 报错 `should like %T%`，必须写成 `LIKE '%FSMS-202%'`。

### 3.4 项目标志位置

`--project-key` 必须放在 `meegle workitem` 域级：

```bash
# ❌ unknown flag
meegle workitem +batch-get --project-key=xxx --work-item-ids ...

# ✅
meegle workitem --project-key=xxx +batch-get --work-item-ids ...
```

---

## 4. 读取飞书文档（requirement-analyzer 专属）

> 与 work-report 不同，requirement-analyzer **必须**读取需求关联的飞书文档正文，
> 因为分析子 Agent 需要完整的 wiki 内容来做代码级分析。

### 4.1 从 description 提取 Wiki URL

Story 的 `description` 字段是 Markdown 字符串，可能包含 wiki 链接。用正则提取：

```
https://<tenant>.feishu.cn/wiki/<token>
```

常见格式：
- `https://gaor4awyz1u.feishu.cn/wiki/Q7l0wOysBiuXkBkNwIPcWawen4d`
- `https://<tenant>.feishu.cn/wiki/<token>?from=...`

提取 token 后，用 lark-wiki 或 lark-doc skill 读取。

### 4.2 使用 lark-wiki skill 读取知识库文档

如果 wiki URL 属于知识库节点：

```bash
# 通过 lark-wiki skill 读取（具体命令由 LLM 自适应）
# 使用 wiki token 作为参数
```

使用 lark-wiki skill 的读取能力获取文档正文，保存为 `_raw/wiki_<token>.md`。

### 4.3 使用 lark-doc skill 读取飞书文档

如果 URL 是普通飞书文档（docx）：

```bash
# 通过 lark-doc skill 读取（具体命令由 LLM 自适应）
```

使用 lark-doc skill 的读取能力获取文档正文，保存为 `_raw/wiki_<token>.md`。

### 4.4 用户直接提供的文档链接

用户在 Step 1 可能直接提供飞书文档链接。处理方式同上：提取 token 后用 lark-wiki/lark-doc skill 读取。

### 4.5 大文档处理

- wiki 内容可能很大（如 `fsms-20260727` 的 wiki_store_risk 是 144KB）
- 保存原始 wiki 内容到 `_raw/wiki_<token>.md`
- 分析子 Agent 会全文读取，LLM 有能力处理大上下文

### 4.6 Wiki 不可用时的降级

- 如果 wiki URL 返回 404 或权限不足 → 在 `_raw/` 目录创建 `wiki_<token>_UNAVAILABLE.md` 记录原因
- 分析子 Agent 仅使用 meegle description 文本作为需求输入
- 在 SUMMARY.md 中标注哪些需求的 wiki 数据不可用

---

## 5. requirement-analyzer 标准查询路径（4 步）

### 步骤 A：认证检查

调 meegle skill 的认证状态命令，确认已登录。

### 步骤 B：MQL 拉取 story 列表

用 meegle skill 的工作项查询能力，参考 `references/meegle-queries.md` 的模板。

- 选 `story` 工作项类型
- 范围：`array_contains(all_participate_persons(), current_login_user())`
- `LIMIT 50`
- 选字段：`work_item_id`, `name`, `status`, `priority`, `description`, `planning_sprint`, `update_time`

### 步骤 C：客户端按迭代过滤

- 在内存中过滤 `planning_sprint[].label` 包含目标迭代名称
- 如果用户指定了需求名称/ID，额外过滤

### 步骤 D：提取 Wiki URL 并读取

- 对每条 story 的 `description` 字段提取 wiki URL
- 对每个 wiki URL，用 lark-wiki/lark-doc skill 读取正文
- 落盘到 `_raw/wiki_<token>.md`

---

## 6. requirement-analyzer 不做的事

- ❌ **不创建/更新飞书工作项**：只读工作流
- ❌ **不写 lark-IM/Sheet/Base 等命令**：只需要 meegle + lark-wiki/lark-doc
- ❌ **不调用 lark-task**：不涉及飞书任务
