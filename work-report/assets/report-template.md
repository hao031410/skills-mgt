# 工作报告（YYYY-MM-DD ~ YYYY-MM-DD）

> **报告人**：<姓名 / 邮箱>
> **报告类型**：<daily | weekly | monthly | custom>
> **生成时间**：<YYYY-MM-DD HH:MM>
> **数据源统计**：
> - 飞书：<拉取 N 条 / 过滤 M 条 / 状态 ok 或 failed>
> - Git：<扫描 X 个子项目 / 共 Y 条 commit>
> - 归并命中率：<Z%>

---

## 一、已完成工作

<!-- 仅列需求项名称（飞书 story name 或 LLM 整理的"其他"项 title），不展开 commit 清单 -->
<!-- 按 status = 已完成/已关闭 的 story 排序 -->

- 需求项 A
- 需求项 B
- 需求项 C
- 需求项 D
- 需求项 E

<!-- 如某需求项需要补充背景说明，可在下一行缩进加注释（可选） -->
  <!-- - 背景：xxx -->

---

## 二、进行中工作

<!-- 按 status = 进行中 的 story 排序 -->

- 需求项 F
- 需求项 G
- 需求项 H

---

## 三、存在的问题

<!-- 来自 status = 已延期/风险/阻塞 的 story + 独立 fix commit -->

- 需求项 I（已延期）：<简述>
- 需求项 J（风险）：<简述>
- 独立问题：<fix commit 主题>

---

## 四、下周计划

<!-- 来自本期"进行中工作" + "未开始" story + WIP/draft commit -->

- 继续推进 需求项 F
- 启动 需求项 K（未开始）
- 需求项 G 的子任务收尾
- 草稿：xxx（WIP）

---

<!-- 可选脚注（不强制） -->

## 附：本期关键 commit 索引

> 仅当用户需要追溯时列出，按子项目分组。

### vanchen/（聚合根）
- `<hash>` <subject>
- `<hash>` <subject>

### backend/fsms/
- `<hash>` <subject>
- `<hash>` <subject>

### backend/scm/
- `<hash>` <subject>

---

## 附：报告生成说明

- 报告由 work-report skill 自动生成
- 模板版本：v1（严格 4 段：已完成/进行中/问题/下周计划）
- 如需修订，请直接编辑本文件后重命名为 `.final.md` 留档
- skill 源码：`/Users/bytego/coder/vanchen/.claude/skills/work-report/`
