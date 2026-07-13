# troubleshooting（work-report 错误处理 FAQ）

> work-report 在执行过程中可能遇到的问题及处理建议。
> 任何错误处理都遵循"不阻断工作流"原则——尽量降级而非失败。

---

## 1. meegle 相关

### 1.1 未登录 / 认证失败

**症状**：

- `meegle auth status` 返回未登录
- 调工作项命令返回 401 / auth error

**处理**：

1. **中断 work-report 工作流**
2. 提示用户执行 meegle skill 的登录命令
3. 用户完成登录后，**重新启动** work-report

**不**自动跑 OAuth（用户主动行为）。

### 1.2 MQL 报错：`required flag(s) "page-num" not set`

**症状**：

- 调 `meegle workitem meta-fields` 时报错

**处理**：

- 在 meegle skill 调用中加 `--page-num 1`
- 这是 meegle CLI 的强制参数，work-report 中所有 meta-* 调用都要带

### 1.3 MQL 报错：`attr label not found`

**症状**：

- MQL 中用了中文名而非 key（如 `工作项ID` 而非 `work_item_id`）

**处理**：

- 改用 key（参见 `references/feishu-integration.md` §3.1）
- 详见 `references/meegle-queries.md` §3 字段 key 速查

### 1.4 MQL 报错：`should like %T%`

**症状**：

- MQL 的 `LIKE` 没加前后 `%`

**处理**：

- 改写为 `%xxx%` 形式

### 1.5 MQL 报错：`attrValueLabel not found`

**症状**：

- `array_contains(\`planning_sprint\`, '<key>')` 用字符串过滤 planning_sprint

**处理**：

- **不能**用 MQL 字符串过滤 planning_sprint
- 改用全量拉 + 客户端按 `planning_sprint[].label` 过滤

### 1.6 MQL 报错：`unknown flag: --project-key`

**症状**：

- `meegle workitem +batch-get --project-key=xxx` 报错

**处理**：

- 把 `--project-key` 放在 `meegle workitem` 域级：`meegle workitem --project-key=xxx +batch-get ...`
- 详见 `references/feishu-integration.md` §3.6

### 1.7 meegle 拉取整体失败（网络/服务不可用）

**症状**：

- 多次重试仍失败
- 返回 5xx 错误

**处理**：

1. 报告头部标注：`飞书数据拉取失败：<具体错误>`
2. 跳过 meegle 阶段，**只用 git 数据**继续
3. 最终报告只显示"已完成/进行中/问题/下周计划"四段，但每段标注"（飞书数据缺失）"
4. 不阻断工作流

### 1.8 description 不含 wiki URL

**症状**：

- 想读 description 正文辅助归并，但 description 是纯文本

**处理**：

- **不读 description 正文**（work-report 不需要）
- 归并只看 status/name/description 头部信息
- 详见 `references/feishu-integration.md` §3.3

### 1.9 拉到的 story 状态字段为 null

**症状**：

- 某些老旧 story 的 status 字段为 null

**处理**：

- 默认归入"进行中工作"段
- 报告头部标注：`<N> 条 story 状态未知，按进行中处理`
- 详见 `references/status-mapping.md` §7.1

---

## 2. git 相关

### 2.1 git log 返回空

**症状**：

- 某子项目在时间窗口内无 commit

**处理**：

- 记录 0 commits，继续下一个子项目
- 报告头部标注：`<子项目名> 本期无 commit 工作`
- 不报错

### 2.2 `git config --global user.email` 返回空

**症状**：

- 用户未配置 git 邮箱

**处理**：

- 报告头部提示：`未配置 git user.email，请用 --user 显式指定`
- **继续扫描所有 commit**（不过滤用户）
- 报告标注：`未过滤用户，<N> 条 commit`

### 2.3 `--author` 过滤后 0 commit

**症状**：

- 用户邮箱与 git 历史中作者邮箱不完全一致

**处理**：

- 提示用户：`用 --author=<name> 试试，或检查邮箱配置`
- 继续执行，但报告标注：`本期无匹配的 commit`

### 2.4 子项目不是 git 仓

**症状**：

- `backend/erp-purchase/` 不是独立 git 仓

**处理**：

- 跳过该子项目，记录"非 git 仓"
- 不报错

### 2.5 git submodule 拉取失败

**症状**：

- `backend/fsms/` 或 `backend/scm/` 子目录为空（submodule 未初始化）

**处理**：

- 提示用户：`submodule <name> 未初始化，请运行 git submodule update --init`
- 跳过该子项目
- 不阻断整体工作流

### 2.6 `--until` 不含当天

**症状**：

- 拉取 `--until=2026-07-12` 时，7.12 的 commit 没被拉取

**处理**：

- 传 `--until=2026-07-13`（即 `to_date + 1 day`）
- 详见 `references/git-conventions.md` §3.2

---

## 3. 归并相关

### 3.1 归并命中率 < 50%

**症状**：

- 大部分 commit 归入了"其他"分类

**可能原因**：

- commit message 没写 `#<story_id>`（显式 ID）
- commit subject 与 story name 关键词重合度低
- 飞书 story name 与 commit 主题描述角度不同

**处理**：

1. 报告头部提示：`归并命中率 <X>%，请人工确认【其他】分类是否合理`
2. **不阻断**生成报告
3. 在 `其他` 段按主题聚类展示

**改进建议**（给用户的提示）：

- 在 commit message 中加 `#<story_id>`（如 `fix(xxx): 修复 yyy #1234`）
- 让 commit subject 关键词更接近飞书 story name

### 3.2 LLM 兜底置信度低

**症状**：

- LLM 对多个 commit 返回 `confidence: "low"` 或 `matched_story_id: null`

**处理**：

- 尊重 LLM 判断，归入"其他"
- 不重试
- 报告头部可标注：`<N> 条 commit LLM 也无法归并，已归入【其他】`

### 3.3 LLM 上下文超限

**症状**：

- 一次 prompt 包含太多 commit（> 10 条），超出 LLM 上下文

**处理**：

- 严格分批：每次最多 10 条 commit
- 详见 `references/merge-strategy.md` §4.2

---

## 4. 报告生成相关

### 4.1 4 段全部为空

**症状**：

- 本期既无飞书 story，也无 git commit

**处理**：

- **不生成报告文件**
- 提示用户：`本期无任何工作记录，是否要生成空报告？`
- 用户确认后，生成只含元数据 + "（本期无任何工作记录）"的报告

### 4.2 报告路径冲突

**症状**：

- 目标文件已存在（如重复跑同一天）

**处理**：

- 询问用户：`文件 <path> 已存在，是否覆盖？`
- 不自动覆盖

### 4.3 用户取消写入

**症状**：

- 用户在"是否写入？"提示后选择"否"

**处理**：

- 把渲染的 Markdown 内容**打印到 stdout**
- 不写文件
- 提示用户：`报告内容已输出到上方，可手动复制`

### 4.4 输出目录不存在

**症状**：

- `docs/reports/` 目录不存在

**处理**：

- 自动创建（用 `mkdir -p`）
- 不报错

---

## 5. 用户输入相关

### 5.1 自然语言时间窗口解析失败

**症状**：

- 用户说"上周三的工作"，但 LLM 解析不出具体日期

**处理**：

- 询问用户确认日期（`2026-07-08`？今天往前推 7-14 天？）
- 不强行猜测

### 5.2 `--type` 与 `--from/--to` 冲突

**症状**：

- 用户给 `--type weekly --from 2026-07-01 --to 2026-07-12`

**处理**：

- `--from/--to` 优先级最高（用户显式指定 > 隐式默认）
- 提示用户：`已使用 --from/--to 覆盖 --type`

### 5.3 `--type=custom` 缺 `--from` 或 `--to`

**症状**：

- 用户给 `--type custom` 但没给 `--from/--to`

**处理**：

- 询问用户补充
- 不默认填值

---

## 6. 环境相关

### 6.1 当前目录不是 git 仓

**症状**：

- 跑 work-report 时当前目录不是 vanchen 聚合根

**处理**：

- 提示用户：`请在 vanchen 聚合根目录运行 work-report`
- 不自动切换目录

### 6.2 meegle skill 未安装

**症状**：

- meegle skill 不可用

**处理**：

- 报告头部标注：`meegle skill 不可用，已跳过飞书数据`
- 只用 git 数据继续
- 不阻断

---

## 7. 不处理的错误

work-report **不处理**以下错误（交由 LLM 工具层）：

- ❌ Bash 命令语法错误（LLM 自身保证）
- ❌ 文件系统权限错误（用户环境问题）
- ❌ 网络连接超时（基础设施问题）
- ❌ meegle CLI 内部 bug（升级修复）

这些情况下，work-report 继续按"降级"原则处理（只用可用的数据源）。

---

## 8. 降级矩阵

| meegle | git | 报告内容 |
|---|---|---|
| ✅ 成功 | ✅ 成功 | 完整 4 段 |
| ✅ 成功 | ❌ 失败 | 完整 4 段（仅飞书数据），头部标注"git 拉取失败" |
| ❌ 失败 | ✅ 成功 | 4 段（仅 git 数据），头部标注"飞书拉取失败" |
| ❌ 失败 | ❌ 失败 | 不生成报告，提示"无数据源可用" |

降级永远不阻断，只标注。
