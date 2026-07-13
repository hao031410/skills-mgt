# status-mapping（meegle status → 报告 4 段映射）

> work-report 在 Step 5（状态判定）阶段使用的映射规则。
> 报告严格 4 段：已完成工作 / 进行中工作 / 存在的问题 / 下周计划

---

## 1. 飞书 story status 映射

| meegle `status` | 报告 section | 触发"存在问题" | 触发"下周计划" |
|---|---|---|---|
| 已完成 | 已完成工作 | ❌ | ❌ |
| 已关闭 | 已完成工作 | ❌ | ❌ |
| 进行中 | 进行中工作 | ❌ | ✅ |
| 未开始 | （不进入本期） | ❌ | ✅（出现在下周计划） |
| 已终止 | （不进入本期） | ❌ | ❌ |
| 已取消 | （不进入本期） | ❌ | ❌ |
| 已延期 | 进行中工作 + 触发"存在问题" | ✅ | ❌ |
| 风险 | 进行中工作 + 触发"存在问题" | ✅ | ❌ |
| 阻塞 | 进行中工作 + 触发"存在问题" | ✅ | ❌ |

**规则**：

1. 已完成/已关闭 → 进入"已完成工作"段
2. 进行中 → 进入"进行中工作"段
3. 未开始 → **不进入**"已完成/进行中"段，但**自动**出现在"下周计划"段（用 story name 作为计划项）
4. 已终止/已取消 → **不进入本期报告**（任何段都不出现）
5. 已延期/风险/阻塞 → 进入"进行中工作"段（因为仍在做），**同时**触发"存在问题"段

---

## 2. 触发"下周计划"的来源

**纯自动推断**，不追问用户。

来源（按优先级）：

1. **本期"进行中工作"段的所有项**：自动衍生为下周计划（取 title）
2. **未开始 story**：取 story name 作为下周计划项
3. **commit message 中含 WIP/draft/partially** 的 commit：取 commit subject 作为下周计划项

**去重**：

- 如果飞书 story 已覆盖的项，commit 衍生项重复时**不**重复列出
- 优先级：飞书 story > commit message

**示例**：

```
飞书: [story A 进行中, story B 未开始]
commits: [
  "WIP: 客户资料分类重构",      # 重复（与 A 相关）
  "fix: 修复定时任务并发",        # 不进入下周计划（进入"问题"）
  "draft: 飞书通知异步化"          # 进入下周计划
]

下周计划输出:
- story A 标题（进行中）
- story B 标题（未开始）
- draft: 飞书通知异步化
```

---

## 3. 触发"存在问题"的来源

**纯自动推断**，不追问用户。

来源（按优先级）：

1. **status = 已延期/风险/阻塞** 的 story：取 story name + status 作为问题项
2. **commit message 中含 `fix:` / `bug:` / `hotfix:` 前缀** 的 commit：取 commit subject 作为问题项
3. **去重**：同一 story 的多条 fix commit 合并为一条问题项

**示例**：

```
飞书: [story A 已延期]
commits: [
  "fix: 修复供应商管控权限过滤",       # 与 A 相关
  "fix(supplierControl): 修复业财分类", # 与 A 相关
  "feat: 新增质量管理措施",             # 不进入问题
  "fix(quartz): 防止多定时任务重复执行"   # 独立问题
]

存在问题输出:
- story A 标题（已延期）
- fix(quartz): 防止多定时任务重复执行
（两条 fix(supplierControl) 合并为一项 = "story A 标题（已延期）"）
```

---

## 4. 4 段输出顺序

报告 4 段**固定顺序**：

1. **已完成工作**（先列完成项，最重要）
2. **进行中工作**（当前在做）
3. **存在的问题**（需要关注的）
4. **下周计划**（展望）

不要按字母序、commit 时间、status 字母序等任何其他顺序。

---

## 5. 段为空时的处理

| 段 | 无数据时显示 |
|---|---|
| 已完成工作 | `（本期无）` |
| 进行中工作 | `（本期无）` |
| 存在的问题 | `（本期无）` |
| 下周计划 | `（本期无）` |

**例外**：

- 4 段全部为空时（如本周完全无工作），报告整体只显示头部元数据 + "（本期无任何工作记录）"
- 此时**不**生成报告文件，建议向用户说明并询问是否需要生成空报告

---

## 6. "其他"分类（未匹配的 commit）

来源：Step 4 归并阶段未匹配到任何 story 的 commit。

**section 判定**：

- commit type = `feat` / `feature` → 倾向"已完成工作"或"进行中工作"（由 LLM 推断）
- commit type = `fix` / `bug` / `hotfix` → 倾向"存在的问题"
- commit type = `WIP` / `draft` / `chore` / `docs` / `refactor` → 倾向"下周计划"或"进行中工作"（由 LLM 推断）
- 标题含"重构"/"迁移"/"升级" → 倾向"已完成工作"或"进行中工作"

LLM 根据 commit subject + 修改文件列表综合判断。

**标题生成**：

- key = `other:<n>`（n 从 1 开始递增）
- title = LLM 根据 commit 内容整理的简洁"需求主题"（如"skill 清理与文档同步"）

---

## 7. 边缘 case

### 7.1 飞书 story 状态字段缺失

如 meegle 返回的 status 为 `null` 或未知字符串：

- 默认归入"进行中工作"段
- 报告头部标注：`<N> 条 story 状态未知，按进行中处理`

### 7.2 commit type 无法识别

commit message 不符合 Conventional Commits 规范（如直接以"修复xxx"开头）：

- LLM 自行判断 type（看动词）
- 标题保持 commit subject 原文

### 7.3 同一 story 在多 commit 中出现

去重：同 story 合并为一条 item，commits 数组累加。

### 7.4 飞书 story 关联到多个迭代

不展开迭代信息，只取第一条 `planning_sprint[0].label` 作为脚注（如需要）。

---

## 8. 状态判定伪代码（LLM 参考）

```python
def determine_section(item: dict) -> str:
    if item.source == "story":
        status = item.raw_story.get("status")
        if status in ("已完成", "已关闭"):
            return "已完成工作"
        elif status in ("已延期", "风险", "阻塞"):
            return "进行中工作"  # 同时触发"问题"
        elif status == "进行中":
            return "进行中工作"
        elif status in ("未开始",):
            return None  # 不进入本期，由"下周计划"承载
        elif status in ("已终止", "已取消"):
            return None
        else:
            return "进行中工作"  # 未知 status 兜底
    elif item.source == "other":
        # LLM 推断
        return llm_infer_section(item)
    return None

def collect_issues(items: list) -> list[str]:
    issues = []
    for item in items:
        if item.source == "story":
            status = item.raw_story.get("status")
            if status in ("已延期", "风险", "阻塞"):
                issues.append(f"{item.title}（{status}）")
        # commit-derived issues 在归并时已合并到对应 story；独立 commit 单独加
    # 加上独立 fix commit
    for commit in unmatched_commits:
        if commit.type in ("fix", "bug", "hotfix"):
            issues.append(commit.subject)
    return dedupe(issues)

def collect_next_week_plan(items: list) -> list[str]:
    plans = []
    for item in items:
        if item.section == "进行中工作":
            plans.append(item.title)
    for story in stories:
        if story.status == "未开始":
            plans.append(story.name)
    for commit in commits:
        if commit.type in ("WIP", "draft") or "partially" in commit.subject.lower():
            plans.append(commit.subject)
    return dedupe(plans, priority="story > commit")
```
