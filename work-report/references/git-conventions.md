# git-conventions（work-report 的 git 拉取规范）

> work-report 在 Step 3（拉取本地 git log）阶段使用的规范。
> 涵盖：子项目发现、用户过滤、commit message 解析、修改文件列表获取。

---

## 1. 子项目自动发现

### 1.1 算法

从当前工作目录（vanchen 聚合根，假设是 `/Users/bytego/coder/vanchen`）开始：

1. 递归扫描所有子目录
2. 凡是包含 `.git/` 目录的路径，识别为一个 git 仓
3. 排除 `.git/` 自身（避免重复处理）
4. 记录每个仓的绝对路径

**vanchen 聚合根的子项目**（截至 2026-07）：

```
vanchen/                     ← 聚合根自身（独立 git 仓）
├── .git/
├── docs/
├── .claude/
└── backend/
    ├── fsms/                ← 子项目（独立 git 仓 + git submodule 指针）
    │   └── .git/
    ├── scm/                 ← 子项目
    │   └── .git/
    └── erp-purchase/        ← 当前不是独立 git 仓（会跳过）
```

**注意**：vanchen 根的 `.gitmodules` 中 `backend/fsms`、`backend/scm` 是 git submodule 形式。在聚合根跑 `git log` **不会**递归进 submodule。需要：

- 用 `git -C <submodule_path> log` 单独拉取
- 或在聚合根用 `git log --recurse-submodules`（会含 submodule 内部 commit）

work-report 默认用**单独跑每个 git 仓**的方式（更可控）。

### 1.2 探测命令

对每个子目录用以下命令探测是否为 git 仓：

```bash
test -d <dir>/.git && echo "git repo"
```

或在 LLM 工具调用中用 `Bash` + `ls`/`stat`。

### 1.3 排除路径

以下路径**不**作为 git 仓扫描：

- `node_modules/`
- `target/`
- `build/`
- `dist/`
- `__pycache__/`
- `.idea/` / `.vscode/`
- `.claude/` / `.agents/` 内部子目录

---

## 2. 用户过滤

### 2.1 默认用户

```bash
git config --global user.email
```

取该邮箱作为默认过滤用户。

### 2.2 多用户

支持两种方式：

1. **`--user` 参数**：CLI 显式指定（覆盖默认）

   ```
   /work-report --user "user1@example.com,user2@example.com"
   ```

2. **`WORK_REPORT_USERS` 环境变量**：逗号分隔多用户

   ```bash
   WORK_REPORT_USERS="user1@example.com,user2@example.com" /work-report
   ```

3. **git log 过滤语法**：

   ```bash
   git log --author="user1@example.com" --author="user2@example.com" ...
   ```

   或用 `--author=user1` + `--author=user2`（多次指定）

### 2.3 用户名 vs 邮箱

`git log --author` 同时支持邮箱和用户名。work-report 默认用邮箱过滤：

```bash
git log --author="<email>" --pretty=format:'...'
```

如需 fallback（邮箱匹配不到时），可同时跑 `--author="<name>"` 取 OR。

### 2.4 用户未配置

`git config --global user.email` 返回空时：

- 报告头部提示：`未配置 git user.email，请用 --user 显式指定`
- 继续扫描所有 commit（不过滤），报告标注：`未过滤用户，<N> 条 commit`

---

## 3. commit 拉取命令

### 3.1 标准命令

```bash
git -C <repo_path> log \
  --since=<from> \
  --until=<to_inclusive+1day> \
  --author=<email> \
  --pretty=format:'%H|%ai|%an|%ae|%s' \
  --no-merges
```

**参数说明**：

- `--since=<from>`：起始时间（含），格式 `YYYY-MM-DD` 或 ISO datetime
- `--until=<to+1day>`：结束时间（**不含**），`git log` 的 `--until` 默认不含当天；为包含 `to` 当天，传 `to+1day`
- `--author=<email>`：单用户过滤（多用户用多次 `--author`）
- `--pretty=format:'%H|%ai|%an|%ae|%s'`：
  - `%H` = commit hash
  - `%ai` = author date (ISO 8601)
  - `%an` = author name
  - `%ae` = author email
  - `%s` = subject
- `--no-merges`：排除 merge commit（merge 通常不含具体工作内容）

### 3.2 时间窗口处理

**关键**：`git log --until=<date>` **不包含** `<date>` 当天。

```python
# Python 等价：
from datetime import datetime, timedelta
to_inclusive = datetime.strptime(to_date, "%Y-%m-%d") + timedelta(days=1)
git_until = to_inclusive.strftime("%Y-%m-%d")
```

或在 bash 中：

```bash
UNTIL=$(date -j -f "%Y-%m-%d" -v+1d "$TO_DATE" +%Y-%m-%d 2>/dev/null \
  || date -d "$TO_DATE + 1 day" +%Y-%m-%d)
git log --until="$UNTIL" ...
```

### 3.3 默认时间窗口（无用户指定）

- weekly：本周一 ~ 今天（周日视为本周最后一天）
- daily：今天 00:00 ~ 今天 23:59
- monthly：本月 1 号 ~ 今天
- custom：用户指定 from/to

---

## 4. commit message 解析

### 4.1 格式规范

vanchen 项目 commit 遵循：

```
<emoji> <type>(<scope>): <subject>

<body>

<footer>
```

**示例**：

```
🐛 fix(supplierControl): 修复业财分类关联逻辑

原逻辑通过业务分类取 itemId，现改为直接通过 itemId 取业财分类。

#1234
```

### 4.2 解析规则

按以下顺序解析：

1. **emoji 提取**：行首第一个 unicode emoji
   - 常见：`🐛` `✨` `📝` `🔥` `🐎` `🚀` `✅` `🔒` `⬆️` `🎨` `⚡` `🛠️` 等
2. **type 提取**：emoji 后第一个单词，括号之前
   - 常见：`feat` `fix` `docs` `style` `refactor` `perf` `test` `chore` `build` `ci` `revert`
3. **scope 提取**：括号内（如果有）
4. **subject 提取**：冒号后第一个换行前
5. **body 提取**：subject 后的空行后内容
6. **footer 提取**：body 后的内容（通常含 `Co-Authored-By` 和 issue 引用）

### 4.3 type 标准化映射

| emoji | type |
|---|---|
| 🐛 | fix |
| 🐞 | fix |
| ✨ | feat |
| 🚀 | feat |
| 📝 | docs |
| 🎨 | style |
| ⚡ | perf |
| 🔥 | chore |
| 🛠️ | refactor |
| ✅ | test |
| ⬆️ | chore (deps) |
| 🔒 | fix (security) |
| 🐎 | perf |
| 🎉 | chore (init) |

如 commit message 不含 emoji，按 type 字符串原样使用（见 §4.2 步骤 2）。

### 4.4 非标准 commit 处理

- **直接以中文动词开头**（如"修复 xxx"、"新增 xxx"）：
  - 标记为 non-conventional
  - LLM 自行判断 type
  - 整体作为 subject 保留
- **merge commit**：已被 `--no-merges` 排除
- **revert commit**：保留，type = `revert`

---

## 5. 修改文件列表（归并阶段使用）

### 5.1 拉取命令

```bash
git -C <repo_path> show --stat --format='' <commit_hash>
```

输出示例：

```
src/main/java/com/example/SupplierControlService.java | 45 ++++++++----
src/main/java/com/example/dto/SupplierDTO.java        | 12 +++--
2 files changed, 38 insertions(+), 19 deletions(-)
```

### 5.2 解析

LLM 关注：

- 文件路径前缀（用于判断 commit 属于哪个模块/包）
- 文件名（用于判断 commit 主题）

### 5.3 何时调用

仅在归并阶段**未匹配**的 commit 上调用（阶段 3 LLM 兜底时提供）：

- 阶段 1（显式 ID 匹配）：不需要 stat
- 阶段 2（标题模糊匹配）：不需要 stat
- 阶段 3（LLM 兜底）：需要 stat

---

## 6. 性能与限制

### 6.1 子项目数

vanchen 当前 3 个子项目（fsms/scm/erp-purchase），其中：

- `fsms/` 是 git submodule，git log 数据量大
- `scm/` 较小
- `erp-purchase/` 非 git 仓

work-report 应在 5 秒内完成所有子项目扫描。

### 6.2 commit 数量

按时间窗口：

- weekly：通常 30-100 条
- monthly：通常 100-500 条
- daily：通常 5-20 条

### 6.3 git log 大输出

如某仓 commit 数 > 1000：考虑分批或加 `--max-count` 限制（但工作流上不应触发）。

---

## 7. work-report 用的 git 命令速查

| 用途 | 命令 |
|---|---|
| 探测 git 仓 | `test -d <dir>/.git` |
| 拉 commit | `git -C <dir> log --since=... --until=... --author=... --pretty=format:'...' --no-merges` |
| 单 commit stat | `git -C <dir> show --stat --format='' <hash>` |
| 取用户邮箱 | `git config --global user.email` |
| 子项目列表 | 读 `.gitmodules` 文件 |

---

## 8. 不要做的事

- ❌ **不进入 submodule 内部跑 git log**（除非用 `git log --recurse-submodules`）
- ❌ **不包含 merge commit**（用 `--no-merges`）
- ❌ **不递归到 `node_modules`/`target` 等**（白名单/黑名单机制）
- ❌ **不修改 commit 内容**：work-report 是只读
- ❌ **不调用 `git push` / `git commit`**：超出 work-report 范围
- ❌ **不解析 `Co-Authored-By` 行**：不影响归并
- ❌ **不解析 commit body 中的复杂格式**（如表格、链接）：只看 subject
