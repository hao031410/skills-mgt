# 产品线 → 仓库映射（通用规范）

> 本文是 requirement-analyzer skill 的通用规范说明，**不绑定任何具体团队 / 仓库 / 用户**。
> 具体的产品线 → Git 仓库路径 → codebase-memory 项目名映射关系，在 skill **运行时动态维护**在：
>
> ```
> <skill输出目录>/config.json
> ```
>
> 默认输出目录为 `docs/requirement-analyzer/config.json`（聚合根相对路径，可在执行时通过 `--output` 覆盖）。

---

## 1. 映射契约（schema）

`config.json` 是单一事实来源（single source of truth），每条记录形如：

```json
{
  "version": 1,
  "mappings": [
    {
      "prefix": "FSMS",
      "product_name": "<产品中文/英文名>",
      "repo_path": "<相对 vanchen 聚合根的路径，如 backend/fsms>",
      "codebase_memory_project": "<codebase-memory list_projects 输出的实际项目名>",
      "status": "ready | needs_index | disabled"
    }
  ]
}
```

**字段说明**：

| 字段 | 必填 | 说明 |
|---|---|---|
| `prefix` | ✅ | 迭代名称前缀（如 `FSMS` 匹配 `FSMS-20260727`） |
| `product_name` | ✅ | 产品线可读名称，用于报告/提示 |
| `repo_path` | ✅ | 相对 vanchen 聚合根的路径（不是绝对路径） |
| `codebase_memory_project` | ✅ | codebase-memory 实际索引后的项目名，**由 `list_projects` 返回，不是从路径推导** |
| `status` | ✅ | `ready` / `needs_index` / `disabled` |

---

## 2. 运行时查找逻辑

requirement-analyzer 在 Step 4（确定产品线 → 仓库映射）阶段：

1. 加载 `<output_dir>/config.json`（不存在时初始化为空文件，见 §4）
2. 从迭代名称提取前缀（`FSMS-20260727` → `FSMS`）
3. 在 `mappings` 中查找 `prefix` 匹配的行
4. **未找到时**：
   - 提示用户提供产品线名称
   - 用户可通过 `--product-line` + `--repo` + `--codebase-memory-project` 参数临时覆盖
   - 执行成功后询问是否写入 `config.json`（持久化）
5. **找到但 `status != ready`**：警告并按映射字段继续（必要时降级为 grep/Glob）
6. **校验**：
   - `repo_path` 存在且含 `.git/`：`test -d <vanchen根>/<repo_path>/.git`
   - `codebase_memory_project` 存在于 `list_projects` 输出
7. 用户可通过 `--product-line` 和 `--repo` 覆盖自动检测（一次性，不写回 config）

---

## 3. 添加新产品线

**添加方式**：**不在本文件中维护**，而是在执行 skill 时：

1. 跑一次 skill，遇到未知前缀时按 §2 步骤 4 提示用户提供信息
2. skill 询问"是否写入 config.json"
3. 确认后新增一条 mapping 记录
4. 若 codebase-memory 尚未索引该仓库，自动跑 `index_repository` 并把 `list_projects` 返回的实际项目名写入

**手动编辑 config.json**（高级用户）也可：

```bash
# 1. 编辑 config.json 加一条 mapping
# 2. 若未索引，跑：
mcp__codebase-memory-mcp__index_repository --repo_path=<vanchen根>/<repo_path>
# 3. 取真实项目名：
mcp__codebase-memory-mcp__list_projects
# 4. 把真实项目名填回 config.json
```

---

## 4. config.json 初始化

文件不存在时，skill 应自动创建骨架：

```json
{
  "version": 1,
  "mappings": []
}
```

并在首次遇到未知前缀时提示用户初始化。

---

## 5. 注意事项

- **前缀匹配是前缀匹配**而非精确匹配（`FSMS-2026` 能匹配 `FSMS` 前缀行）
- 如果迭代名称不包含任何已知前缀，需用户手动指定产品线（`--product-line`）
- `codebase_memory_project` 字段必须从 `list_projects` 实际输出取值，**不能从 `repo_path` 字符串推导**（codebase-memory 的命名规则与运行环境相关）
- `config.json` 应加入 `.gitignore` 聚合根的忽略清单（如已是聚合根内 `.gitignore` 的一部分）——它是**环境配置**而非**业务产物**，是否入库由各团队决定
