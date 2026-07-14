---
name: requirement-analyzer
description: 从飞书项目拉取指定迭代的需求，读取关联飞书文档，启动代码分析子Agent生成结构化分析文档（8章节双证据格式），并由审核Agent把关质量。当用户输入 "/requirement-analyzer" 或表达"分析需求""需求分析""分析迭代需求"等需求时触发。
---

# requirement-analyzer skill

## 触发

用户表达包括但不限于：

- `/requirement-analyzer --iteration FSMS-20260727`（分析指定迭代）
- `/requirement-analyzer --iteration FSMS-20260727 --name "供应商审核"`（按需求名称筛选）
- `/requirement-analyzer --iteration FSMS-20260727 --doc https://xxx.feishu.cn/wiki/xxx`（附带飞书文档链接）
- `/requirement-analyzer --from-snapshot 240713-a1b2c3d4`（复用已有快照，跳过飞书拉取）
- "分析 FSMS-20260727 迭代的需求"
- "帮我分析一下供应商审核这个需求"

## 工作流（7 步）

### Step 1：解析用户输入与配置

**必填参数**：

| 参数 | 说明 | 示例 |
|------|------|------|
| `--iteration` | 迭代名称，支持逗号分隔多个 | `FSMS-20260727` 或 `FSMS-20260727,FSMS-20260810` |

**可选参数**：

| 参数 | 说明 |
|------|------|
| `--name` | 需求标题子串或 work_item_id 筛选 |
| `--doc` | 附加的飞书文档/wiki URL，补充到需求输入中 |
| `--product-line` | 手动指定产品线（覆盖自动检测） |
| `--repo` | 手动指定 Git 仓库路径（覆盖映射表） |
| `--slug` | 自定义输出目录标识（默认从产品线 key 或迭代名推导） |
| `--from-snapshot` | 复用已有的 `_raw/` 快照目录（格式 `yyMMdd-slug`），跳过 Step 2-3 |
| `--output` | 指定输出目录（默认 `docs/requirement-analyzer/<yyMMdd>-<slug>/`） |

**默认行为**：
- 产品线自动检测：从迭代名称提取前缀（`FSMS-20260727` → `FSMS`），查 `references/product-line-mapping.md`
- 默认 meegle 空间：`xlb`（`project_key=65eef07569082b29c300cc80`）
- 默认输出：`docs/requirement-analyzer/<yyMMdd>-<slug>/`
  - `yyMMdd` = 当前日期（如 `240713`）
  - `slug` = 优先级：用户 `--slug` 参数 > 首个迭代名小写下划线转连字符（如 `fsms-20260727`）> 产品线 key 小写（如 `fsms`）

### Step 2：从飞书拉取需求

> **如果用户指定了 `--from-snapshot`，跳过此步**，直接从已有快照目录读取 `_raw/` 下的文件。

1. **认证检查**：调用 meegle skill 的认证状态命令。未登录则中断并提示 `meegle auth login`。

2. **MQL 查询**：参考 `references/meegle-queries.md` 的标准模板，拉取"我参与的"story 列表（不限状态）。

3. **客户端过滤**：在内存中按 `planning_sprint[].label` 过滤匹配用户指定的迭代名称。如果用户指定了 `--name`，额外按标题子串或 work_item_id 过滤。

4. **原始数据保存**：每条 story 的完整 payload 保存为 `_raw/story_<work_item_id>.json`。

5. **空结果处理**：
   - 所有迭代均为 0 条 → 中断，提示核实迭代名称
   - 部分迭代为 0 条 → 警告并跳过空迭代

### Step 3：读取关联飞书文档

> **如果用户指定了 `--from-snapshot`，跳过此步**。

对每条 story 的 `description` 字段：

1. 提取 wiki URL（正则：`https://<tenant>.feishu.cn/wiki/<token>`）
2. 解析用户通过 `--doc` 参数提供的附加文档链接
3. 对每个 wiki URL，使用 lark-wiki 或 lark-doc skill 读取完整正文
4. 保存到 `_raw/wiki_<token>.md`

**降级处理**：如果某个 wiki URL 不可访问，创建 `_raw/wiki_<token>_UNAVAILABLE.md` 记录原因。分析子 Agent 将仅使用 meegle description 文本。

### Step 4：确定产品线 → 仓库映射

查 `references/product-line-mapping.md`：

1. 从迭代名称提取前缀（`FSMS-` → `FSMS`）
2. 查映射表获取 Git 仓库路径和 codebase-memory 项目名
3. 验证：`test -d <vanchen根>/<git_repo_path>/.git`
4. 验证 codebase-memory 索引状态（`index_status`）
5. 用户可通过 `--product-line` 和 `--repo` 覆盖自动检测

**降级**：
- 无映射的产品线 → 警告并跳过
- codebase-memory 索引缺失 → 降级为 grep/Glob 搜索

### Step 5：并行启动分析子 Agent

为每条需求启动一个独立的 Agent（使用 `Agent` 工具，type=`general-purpose`），**并行执行**。

每个分析 Agent 接收以下输入（在主 skill 的 prompt 中组装）：

```
你是一个后端需求分析专家。请对以下需求进行代码级深度分析。

## 需求信息
- 标题：<story.name>
- 描述：<story.description 文本>
- 优先级：<story.priority>
- 飞书文档：<wiki 文件路径或"无">

## 产品线信息
- 产品线：<product_line_name>
- Git 仓库：<vanchen根>/<git_repo_path>
- codebase-memory 项目：<project_name>

## 输出要求
- 输出文件：<output_dir>/迭代<N>/<序号>-<slug>.md
- 模板文件：assets/req-analysis-template.md
- 系统提示词：references/agent-prompts.md（分析 Agent 部分）

请严格按照模板的 8 章节格式生成分析文档，遵守双证据原则。
完成后返回结构化的 YAML 摘要。
```

**重要**：分析 Agent 的系统提示词（完整版）见 `references/agent-prompts.md` 的"分析 Agent"部分。主 skill 在调用 Agent 时需将此内容注入 prompt。

**并行策略**：
- 所有需求分析 Agent 同时启动（需求间无依赖）
- 等待所有 Agent 完成后汇总结果

**错误处理**：
- 单个 Agent 失败：标记为"分析失败"，继续其余需求
- 所有 Agent 失败：中断并报告

### Step 6：生成汇总文档

所有分析 Agent 完成后：

1. **汇总各 Agent 的返回结果**，提取每条需求的：
   - 完成度判定（YES/NO/PARTIAL）
   - 关键 commit
   - 是否需要补做
   - 核心风险

2. **生成 `SUMMARY.md`**：按 `assets/summary-template.md` 模板填充
   - 元数据块（分析时间、用户、产品线、迭代）
   - 总览表（标题、飞书状态、代码完成度、关键 commit、是否需要补做）
   - 整体结论段落
   - 按需求逐一摘要（300-500字，从 Agent 返回提取）
   - 整体行动顺序（P0/P1/P2/P3，按风险/急迫度排序）
   - 输出文件清单

3. **审核状态标记**：SUMMARY.md 暂标记为"⏳ 待审核"，Step 7 审核完成后更新。

### Step 7：启动审核 Agent

启动一个独立的审核 Agent（type=`general-purpose`）。

审核 Agent 接收以下输入：

```
你是一个代码分析文档质量审核专家。请对以下需求分析文档进行全面审核。

## 审核范围
- 输出目录：<output_dir>
- Git 仓库：<repo_path>
- codebase-memory 项目：<project_name>

## 审核要求
- 检查清单：references/quality-checklist.md
- 系统提示词：references/agent-prompts.md（审核 Agent 部分）

请按检查清单逐项验证，发现问题直接修复并记录修改日志。
审核完成后更新 SUMMARY.md 的审核状态标记。
```

审核 Agent 的完整系统提示词见 `references/agent-prompts.md` 的"审核 Agent"部分。

**审核输出**：
- 在每条修改过的文档末尾追加"修改日志"表格
- 在 SUMMARY.md 中更新审核状态和审核结论
- 返回审核结果 YAML

**审核失败降级**：如果审核 Agent 执行失败，在 SUMMARY.md 中标注"⚠️ 未经审核"，输出文档仍可用。

---

## 输出目录结构

```
docs/requirement-analyzer/<yyMMdd>-<slug>/
├── SUMMARY.md                  # 需求总览汇总
├── _raw/                       # 原始快照（审计追溯）
│   ├── story_<id>.json
│   └── wiki_<token>.md
├── FSMS-20260727/              # 按规划迭代名分目录
│   ├── 01-<slug>.md
│   └── 02-<slug>.md
└── fsms/                       # 无规划迭代 → 产品线 key 小写
    └── 01-<slug>.md
```

- `yyMMdd`：分析执行日期（如 `240713`）
- `slug`（外层）：目录标识符，优先级为用户指定 > 首个迭代名（如 `FSMS-20260727`→`fsms-20260727`）> 产品线 key 小写（如 `fsms`）
- `<迭代名>`（子目录）：取 story 的 `planning_sprint[].label` 为目录名（如 `FSMS-20260727`）；无规划迭代则用产品线 key 小写（如 `fsms`）
- `<slug>`（文件名）：从需求标题提取的英文短标识（如 `user-auth-refactor`）
- 序号 `01`、`02` 在迭代目录内编号（两位数字，零填充）

---

## 中间产物（LLM 内存中维护）

不需要写入文件，LLM 在执行过程中维护：

```yaml
session:
  session_id: "<yyMMdd>-<slug>"
  output_dir: "docs/requirement-analyzer/<yyMMdd>-<slug>"
  created_at: "<ISO timestamp>"

config:
  iterations: ["FSMS-20260727"]
  product_line: "FSMS"
  repo_path: "<vanchen根>/backend/fsms"
  codebase_memory_project: "<list_projects 实际返回的项目名>"
  from_snapshot: null

source_stats:
  meegle:
    fetched: <N>
    filtered: <M>
    status: "ok" | "failed"
    error: null | "<reason>"
  wiki:
    total: <N>
    success: <M>
    failed: <K>

requirements:
  - id: "story#<work_item_id>"
    title: "<name>"
    status: "<meegle status>"
    priority: "<P1/P2/P3>"
    iteration: "<迭代名>"
    has_wiki: true | false
    wiki_file: "_raw/wiki_<token>.md" | null
    agent_status: "pending" | "running" | "done" | "failed"
    agent_result:
      completion_judgment: "YES" | "NO" | "PARTIAL"
      output_file: "迭代<N>/<序号>-<slug>.md"
      error: null | "<reason>"

review:
  status: "pending" | "running" | "done" | "failed"
  result:
    review_verdict: "PASS" | "NEEDS_REVISION" | "FAILED"
    issues_found: <N>
    issues_fixed: <N>
```

---

## 错误处理

详见 `references/troubleshooting.md`。

| 场景 | 级别 | 处理 |
|------|------|------|
| meegle 未认证 | 阻断 | 提示 `meegle auth login`，终止 |
| 所有迭代 0 条需求 | 阻断 | 提示核实迭代名，终止 |
| 所有分析 Agent 失败 | 阻断 | 终止并报告 |
| 部分迭代 0 条需求 | 警告 | 跳过空迭代，继续 |
| 产品线无映射 | 警告 | 提示用户，跳过无映射需求 |
| codebase-memory 索引缺失 | 警告 | 降级为 grep，标注在文档中 |
| 单个 wiki 不可访问 | 警告 | 标注"不可用"，用 description 继续 |
| 单个分析 Agent 失败 | 警告 | 标记"分析失败"，继续其余 |
| 审核 Agent 失败 | 信息 | 标注"未经审核"，输出仍可用 |

---

## 不要做的事

- ❌ **不写 Python 脚本**（由 LLM 自适应调用 meegle/lark skill）
- ❌ **不调任何固定的 meegle/lark 子命令**（由 LLM 调对应 skill 自适应最新接口）
- ❌ **不写单元测试**（无脚本可测；正确性靠人工 review 和实际运行验证）
- ❌ **不预设代码修改方案**（修改建议由分析 Agent 基于实际代码状态生成，主 skill 不预设）
- ❌ **不跨 session 缓存飞书数据**（每次执行重新拉取，除非用户显式指定 `--from-snapshot`）
- ❌ **不修改子项目文件**（只输出分析文档到聚合根 `docs/requirement-analyzer/`）
- ❌ **不实现增量分析**（每次全量分析指定迭代，不复用历史分析结果）
- ❌ **不调用 `backend/*/src/` 外的代码修改工具**

---

## 相关 references

- `references/product-line-mapping.md` — 产品线 → 仓库路径 + codebase-memory 项目映射
- `references/meegle-queries.md` — MQL 查询模板
- `references/feishu-integration.md` — meegle 认证、lark-doc/lark-wiki 读取、踩坑清单
- `references/agent-prompts.md` — 分析 Agent + 审核 Agent 完整系统提示词
- `references/quality-checklist.md` — 审核 Agent 检查清单（6 大类）
- `references/troubleshooting.md` — 错误处理 + 降级矩阵
- `assets/req-analysis-template.md` — 单需求分析文档模板（8 章节）
- `assets/summary-template.md` — 汇总文档模板
