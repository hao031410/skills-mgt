# merge-strategy（commit → story 三阶段归并算法）

> work-report 在 Step 4（归并）阶段使用的算法。
> 目标：把每个 git commit 归并到对应的飞书 story（key=`story#<id>`），未匹配的归入"其他"（key=`other:<n>`）。

---

## 1. 总体流程

```
输入：
  - stories: 从 meegle 拉到的本期 story 列表（含 work_item_id, name, status, ...）
  - commits: 从 git log 拉到的本期 commit 列表（含 hash, subject, type, files, ...）

三阶段处理：
  ┌─────────────────────────────────────────────┐
  │ 阶段 1：显式 ID 匹配（精确）                  │
  │ - 正则提取 commit message 中的 workitem id   │
  │ - 直接归并                                   │
  └─────────────────────────────────────────────┘
            ↓ (剩余未匹配)
  ┌─────────────────────────────────────────────┐
  │ 阶段 2：标题模糊匹配（统计）                  │
  │ - Jaccard 相似度 ≥ 0.4                       │
  │ - 取最高分命中                                │
  └─────────────────────────────────────────────┘
            ↓ (剩余未匹配)
  ┌─────────────────────────────────────────────┐
  │ 阶段 3：LLM 智能兜底                          │
  │ - 一次最多 10 条合并 prompt                    │
  │ - LLM 给 story key 或 null                    │
  └─────────────────────────────────────────────┘
            ↓ (剩余仍未匹配)
  ┌─────────────────────────────────────────────┐
  │ 阶段 4：归入"其他"                            │
  │ - key = "other:<n>"                          │
  │ - title = LLM 整理                            │
  └─────────────────────────────────────────────┘

输出：
  - items: 归并后的列表
  - unmatched_commits: 未匹配的 commit 列表（供"下周计划"/"问题"判定）
```

---

## 2. 阶段 1：显式 ID 匹配

### 2.1 提取规则

按以下顺序尝试匹配 commit message 中的 workitem id：

1. `#1234` 形式：正则 `\B#(\d{4,})\b`（避免匹配 `## ` 等 markdown 标题）
2. `xlb-1234` 形式：正则 `\bxlb-(\d{4,})\b`
3. `XLB1234` 形式：正则 `\bXLB(\d{4,})\b`（少见）
4. 纯数字：正则 `\b(\d{6,})\b`（workitem id 通常是 6 位数以上；保守匹配，避免误命中）

提取到数字后：

- 在 `stories` 中查找 `work_item_id == <extracted_id>`
- 找到 → 归并到 `key: "story#<id>"`
- 找不到（如 commit 提到的 ID 不在本期 story 列表中）→ 不归并，进入阶段 2

### 2.2 多 ID 匹配

commit message 含多个 ID（如 `feat(x): 关联 #1234 #5678`）：

- 全部归并：commit 同时属于 `story#1234` 和 `story#5678`
- 即：commit hash 加入两个 story 的 `commits` 数组

### 2.3 命中优先级

- 阶段 1 命中后**不再**进入阶段 2
- 即：显式 ID 优先于模糊匹配

---

## 3. 阶段 2：标题模糊匹配

### 3.1 算法

对每个未匹配 commit：

1. 提取 commit subject 的关键词集合：
   - 分词（中文按字符，英文按 word）
   - 去停用词（的/了/是/in/on/at/...）
   - 取前 10 个关键词
2. 对每个 story，计算关键词集合的 Jaccard 相似度：

   ```
   J(story, commit) = |story_keywords ∩ commit_keywords| / |story_keywords ∪ commit_keywords|
   ```

3. 选**最高分** story：
   - 最高分 ≥ 0.4 → 归并
   - 最高分 < 0.4 → 不归并，进入阶段 3

### 3.2 备选算法

- **编辑距离**：subject 与 story name 的 Levenshtein 距离
- **TF-IDF + cosine**：用词频而非纯关键词

work-report 默认用 Jaccard（简单、可解释）。如发现命中率低，可换 TF-IDF。

### 3.3 关键词提取细节

- 中文：用 `jieba` 或简单字符级 n-gram（bigram）
- 英文：split by `[^a-zA-Z]+`，转小写
- 停用词：内置一份（的/了/是/the/a/an/...）

### 3.4 命中后处理

- 归并到 `key: "story#<id>"`
- 同一 commit 可归并到多个 story（如果标题模糊命中多个，Jaccard 都 ≥ 0.4）

---

## 4. 阶段 3：LLM 智能兜底

### 4.1 触发条件

阶段 2 之后**仍未匹配**的 commit。

### 4.2 批处理

- 一次 prompt 处理**最多 10 条** commit（避免单次 prompt 过大）
- 超过 10 条：分批处理

### 4.3 prompt 设计

给 LLM 的输入：

```yaml
stories: [
  {work_item_id: 1234, name: "供应商管控-处罚单生成", status: "进行中"},
  {work_item_id: 5678, name: "客户资料分类重构", status: "进行中"},
  ...
]
unmatched_commits: [
  {
    hash: "abc123",
    subject: "feat(supplier): 调整管控分页",
    files: ["src/main/.../SupplierControlService.java", ...]
  },
  ...
]
```

LLM 输出（YAML 格式）：

```yaml
- hash: "abc123"
  matched_story_id: 1234     # 或 null
  confidence: "high" | "medium" | "low"
  reason: "..."
- hash: "def456"
  matched_story_id: null
  confidence: "low"
  reason: "..."
```

### 4.4 命中后处理

- `matched_story_id != null` 且 `confidence != "low"` → 归并
- `matched_story_id == null` 或 `confidence == "low"` → 进入阶段 4

### 4.5 LLM 调用注意事项

- 单次最多 10 条 commit，避免 token 超限
- 提供完整的 stories 列表（不省略）让 LLM 选
- 提供每个 commit 的 `git show --stat` 修改文件列表
- 接受 LLM 给出 `null`，不强制命中

---

## 5. 阶段 4：归入"其他"

### 5.1 key 命名

- 格式：`other:<n>`，n 从 1 开始递增
- 同一 work-report 中 key 唯一

### 5.2 title 生成

LLM 根据 commit 内容生成：

- 取 commit subject 第一行作为候选
- LLM 改写为简洁的"需求主题"形式
- 多个 commit 归入同一"其他"项时（如 `git log` 显示几个连续的 skill 清理 commit），LLM 综合给一个总标题

**示例**：

```
输入 commits:
- "remove(agents-skills): 移除 .agents/skills/ 下未使用的 git-auto-cp skill"
- "remove(claude-skills): 移除 .claude/skills/ 下未使用的 git-auto-cp skill"
- "chore(root): 清理 weekly-report skill + 收紧 .gitignore"

输出:
- key: "other:1"
  title: "skill 清理与 .gitignore 收紧"
  commits: [hash1, hash2, hash3]
```

### 5.3 section 判定

详见 `references/status-mapping.md` §6：
- `feat`/`feature` → 倾向"已完成/进行中"
- `fix`/`bug`/`hotfix` → 倾向"问题"
- `WIP`/`draft`/`chore`/`refactor` → 倾向"下周计划"或"进行中"

LLM 综合判断。

---

## 6. 归并产物结构

```yaml
items:
  - key: "story#1234"
    title: "供应商管控-处罚单生成"
    source: "story"
    section: "进行中工作"           # 由 status-mapping 决定
    commits: ["abc123", "def456"]
    raw_story: {...}               # 飞书原始 payload（可选保留）

  - key: "other:1"
    title: "skill 清理与 .gitignore 收紧"
    source: "other"
    section: "已完成工作"            # 由 LLM 推断
    commits: ["ghi789", "jkl012"]
    raw_commits: [...]             # git 原始 payload（可选保留）
```

---

## 7. 命中率提示

归并结束后：

- `matched_to_story = sum(commits linked to story)` / `total_commits`
- 命中率 < 50% → 报告头部提示：`归并命中率 <X%，请人工确认【其他】分类是否合理`
- 命中率 < 20% → 进一步提示：`【其他】项较多，建议检查 commit message 是否应包含 #<story_id>`

**不阻止生成报告**，只提示。

---

## 8. 不要做的事

- ❌ **不解析 description 中的需求正文**：归并只看 commit subject + 文件名 + 飞书 story name
- ❌ **不创建飞书工作项**：归并是只读操作
- ❌ **不强制 LLM 命中**：LLM 给出 null 时不重试，直接归入"其他"
- ❌ **不预设 commit 优先级**：每个 commit 独立归并
- ❌ **不跨工作项类型归并**：story 只跟 story 配对，issue/sub_task 当前不需要归并（除非未来扩展）
- ❌ **不重命名飞书 story**：用 meegle 返回的 `name` 原样
