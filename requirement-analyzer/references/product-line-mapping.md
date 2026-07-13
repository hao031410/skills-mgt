# 产品线 → 仓库映射表

> 此表将产品线标识映射到 Git 仓库路径和 codebase-memory 项目名。
> **添加新产品线时**：在表中新增一行，确保仓库路径和索引状态正确。

---

## 当前映射

| 前缀 | 产品名称 | Git 仓库路径（相对 vanchen） | codebase-memory 项目 | 状态 |
|------|---------|---------------------------|---------------------|------|
| FSMS | 食品安全管理系统 | `backend/fsms` | `Users-bytego-coder-vanchen-fsms` | ✅ 已就绪 |

## 预留映射（待补充）

| 前缀 | 产品名称 | Git 仓库路径（相对 vanchen） | codebase-memory 项目 | 状态 |
|------|---------|---------------------------|---------------------|------|
| SCM | 供应链管理系统 | `backend/scm` | `Users-bytego-coder-vanchen-scm` | ⏳ 待索引 |
| ERP | ERP 采购系统 | `backend/erp-purchase` | `Users-bytego-coder-vanchen-erp-purchase` | ⏳ 待索引 |

---

## 映射查找逻辑

1. 从迭代名称提取前缀（如 `FSMS-20260727` → `FSMS`）
2. 在此表中查找前缀匹配行
3. 检查仓库路径是否存在：`test -d <vanchen根>/<git_repo_path>/.git`
4. 检查 codebase-memory 索引状态：调用 `index_status` 验证
5. 若前缀无匹配 → 提示用户提供产品线名称，或在此表中添加映射

---

## 添加新产品线步骤

1. 在"当前映射"表中新增一行，填写所有列
2. 确保 Git 仓库路径存在且有 `.git/` 目录
3. 对仓库执行 codebase-memory 索引：`mcp__codebase-memory-mcp__index_repository`
4. 更新 `codebase-memory 项目` 列填写索引后的项目名称
5. 将状态改为 ✅ 已就绪

---

## 注意事项

- 前缀匹配是**前缀匹配**而非精确匹配（`FSMS-2026` 能匹配 `FSMS` 前缀行）
- 如果迭代名称不包含已知前缀（如纯日期格式），需用户手动指定产品线
- 一个迭代可能不包含任何已知产品线的前缀，此时需用户指定 `--product-line` 参数
- 预留映射中的产品线会在首次使用时提示用户确认是否可用
