---
name: vanchen-e2e
description: 在 VanchEN 测试环境执行需求驱动的端到端页面测试。用于根据用户给出的模块名、菜单路径或测试描述定位页面，完成 FSMS食品安全及后续已索引模块的导航、查询、详情和显式授权的写操作；支持将不同菜单分配给多个 agent 并行验证。
---

# VanchEN E2E

使用 `ego-browser` 操作真实页面。先读取仓库的 `docs/e2e/config.json`；若项目尚未有该文件，复制本 skill 的 `assets/config.json.template` 后再填入实测内容。

选择 `active_environment` 作为默认环境。用户明确指定其他环境时，只允许使用配置中 `enabled: true` 且 URL 非空的环境；否则停止并要求维护人先补全该环境配置。当前项目只启用测试环境。

将索引视为首选的已验证导航索引，而非运行事实。页面与索引不一致时，以真实 UI 为准，记录差异并由主 agent 审核后更新；不臆测路径、URL 或接口。

## 快速开始

本 skill 所有浏览器操作通过 `ego-browser nodejs <<'EOF' ... EOF` heredoc 执行。

```bash
ego-browser nodejs <<'EOF'
const task = await ego.helpers.useOrCreateTaskSpace('vanchen-e2e-<task-name>')
await ego.helpers.openOrReuseTab(ENV_URL, { wait: true, timeout: 30000 })
await ego.helpers.waitForLoad('networkidle', { timeout: 30000 })
await ego.helpers.wait(2)                 // 单位秒,用于视觉稳定
EOF
```

> **重要**:本模式下所有 helper 只在 `ego.helpers.*` 下,SKILL 旧示例里的 `page.xxx` /
> `browser.xxx` / `taskSpaces.xxx` 都不工作。facade 速查、参数类型、常见错误见
> [references/ego-browser-api.md](references/ego-browser-api.md)。

## 接收需求

要求用户给出模块名称和测试目标。若模块、目标菜单或预期结果缺失，先澄清，不自行选择模块或写操作。

将自然语言需求解析为：

```text
模块 / 一级导航 / 分组标题 / 子菜单 / 操作与断言
```

FSMS 的完整路径必须保留分组标题,例如:`FSMS食品安全 / 档案 / 供应商审核 / 审核模板`。

## 定位并进入页面

1. 创建或复用本测试的独立 task space,打开选定环境。
2. 若当前模块不是用户指定模块,视觉点击顶部九宫格,按 `config.json` 中的模块名选择模块;切换后验证左侧模块标题。
3. 对 FSMS,按"页面稳定 → 左侧一级导航 → 悬停弹层 → 在弹层内点击子菜单 → 顶部 Tab → 列表页"进入页面。首次打开页面或刚打开上一子菜单后,先等待网络空闲,再额外等待约 3 秒;不要在加载骨架、旧 Tab 切换动画或弹层内容尚未更新时 hover。
4. 切换到另一个一级导航前,**用真实鼠标 hover 到页面主体的安全空白区**(坐标约 `[800, 600]`)并等待约 1 秒,让旧弹层关闭。不要用合成 `MouseEvent('mousemove')` 事件(可能不触发 React handler)。
5. 再动态获取目标**一级导航外层可悬停区域**的可见中心点,真实 hover 后等待约 3 秒,让新弹层内容完成切换。**不要复用固定坐标、固定 CSS/XPath 或旧 `@N` ref**;不要依赖"所属模块分类"这种 a11y 复用的按钮名。

### 一级导航 hover 的动态坐标模板

```js
const navPoint = await ego.helpers.js(`(() => {
  const wanted = ['看板','档案','供应链','仓储','店铺','合规','数据']; // 按当前模块替换
  for (const name of wanted) {
    const nodes = Array.from(document.querySelectorAll('button,div,span'));
    for (const n of nodes) {
      if ((n.textContent || '').trim() === name) {
        const r = n.getBoundingClientRect();
        if (r.width > 0 && r.height > 0 && r.top > 60 && r.left < 250) {
          return { x: r.left + r.width/2, y: r.top + r.height/2 };
        }
      }
    }
  }
  return null;
})()`)
if (!navPoint) throw new Error('一级导航未找到')
```

6. **将可见弹层作为点击子菜单的硬前置条件。** 只有目标一级菜单已 hover、弹层在截图或 DOM 中可见、且弹层内同时出现目标分组标题和子菜单精确文本时,才允许点击子菜单。侧栏高亮、悬停提示、旧弹层残留或索引中存在该菜单,都不能代替弹层证据。
7. **在同一 heredoc 中原子完成菜单动作**:hover 一级菜单 → 等待新弹层稳定 → 动态取得弹层内目标子菜单的可见坐标 → 鼠标连续移入该坐标 → click。此阶段不得插入截图、`snapshotText()`、`cliLog()` 后等待、滚动、回到页面主体或另起 heredoc;这些操作都可能让鼠标离开弹层,使后续点击无效。允许在不移动鼠标的前提下用 `js()` 读取精确菜单文本的可见坐标。
8. 弹层未出现、目标文本不在弹层内或坐标不可见时,**禁止点击页面主体中任何同名文本**。先把鼠标移出侧栏,截图记录"弹层未出现"或"菜单文本不匹配",再重新 hover;连续两次失败则 handoff 给用户完成导航,收到用户明确"继续"后才 take over。
9. 点击后才能鼠标移出弹层并做截图/语义快照;先等待网络空闲并额外等待约 2 秒,再断言页面状态。判定进入成功的标准见下节"进入成功的判定"。
10. 已在当前 Tab 的目标页面不重复打开;先用 Tab 与页面特征确认状态。

### FSMS 弹层导航的稳定模式

FSMS 弹层容器有稳定 className(实测):

- `menu_detail_container___2_08m` — 弹层外框
- `menu_detail_item___1KQ2S` — 分组块(含分组标题与该分组下的子菜单)
- `menu_content___2ZjsJ` — 子菜单条目

**不要**用"弹层 textContent 必须同时包含分组标题和子菜单文本"作为唯一锚点,
因为 `<html>` 根节点也含这些文本,会导致误命中。**必须**先用 className 圈定弹层。

```js
// === 关闭旧弹层 ===
await ego.helpers.hover([800, 600])
await ego.helpers.wait(1)

// === hover 一级菜单(动态坐标) ===
const navPoint = await ego.helpers.js(/* 见上节 */)
await ego.helpers.hover([navPoint.x, navPoint.y])
await ego.helpers.wait(3)  // 弹层稳定,实测 3s 比 2s 更稳

// === 在弹层内找精确文本节点(className 锚定) ===
const target = await ego.helpers.js(`(() => {
  const GROUP = '供应商审核';  // 替换为当前分组名
  const TARGET = '审核模板';  // 替换为当前子菜单名
  const containers = Array.from(document.querySelectorAll('div'));
  let popup = null;
  for (const el of containers) {
    if (!(el.className || '').toString().includes('menu_detail_container')) continue;
    const popover = el.closest('.ant-popover');
    if (!popover || popover.classList.contains('ant-popover-hidden')) continue;
    const r = el.getBoundingClientRect();
    const s = window.getComputedStyle(el);
    if (r.width < 200) continue;
    if (s.display === 'none' || parseFloat(s.opacity) === 0) continue;
    if (el.closest('.menu_container___1zSTm')) continue;  // 排除侧栏本体内嵌的同名元素
    if (!(el.textContent || '').includes(GROUP)) continue;
    popup = el; break;
  }
  if (!popup) return { found: false, reason: 'popup not visible' };
  for (const n of popup.querySelectorAll('div, span')) {
    if ((n.textContent || '').trim() === TARGET) {
      const r = n.getBoundingClientRect();
      const cs = window.getComputedStyle(n);
      if (r.width > 0 && r.height > 0 && cs.display !== 'none' && parseFloat(cs.opacity) > 0) {
        return { found: true, x: r.left + r.width/2, y: r.top + r.height/2 };
      }
    }
  }
  return { found: false, reason: 'menu text not found in popup' };
})()`)
if (!target.found) throw new Error('弹层未出现或菜单文本不匹配: ' + target.reason)

// === hover + click(原子动作) ===
await ego.helpers.hover([target.x, target.y])
await ego.helpers.click([target.x, target.y])
await ego.helpers.waitForNetworkIdle({ timeout: 30 })
await ego.helpers.wait(2)
// 此后才允许 captureScreenshot / snapshotText
```

## 进入成功的判定

**所有菜单的硬条件(必须同时满足)**:

1. 顶部存在目标名称的 Tab，且该 Tab 处于激活状态；首次进入时会新增该 Tab，已打开时复用该 Tab。
2. 列表/详情/看板 至少属于下表一种页面类型,并出现该类型的独有特征。

**页面类型识别表**:

| 类型 | 特征关键字(任一即可) | 示例 |
| --- | --- | --- |
| 列表 | `查询` / `导出` / `新增` / `共 N 条` / `序号` 表头 / 分页器 | 审核模板、政府抽检明细 |
| 详情/表单 | `保存` / `提交` / `取消` / `添加提醒` / 输入框 ≥ 2 个 | 消息提醒、经营项目管理 |
| 看板 | `radio` / 图表容器 / `总计` `集采` `地采` 等分类 / 数字卡(KPI) | FSMS看板 |

只满足硬条件 1 但页面是空白骨架或仍显示旧 Tab 内容,判定为**页面断言失败**。

## 执行测试

- 查询数据时,填写用户要求的筛选条件后点击「查询」,等待加载结束,再以数据行、空态或分页总数断言结果。
- 列表页使用语义快照定位「查询」「新增」「删除」「导出」、筛选字段、表头和分页器;不要把菜单阶段的视觉定位方式延伸到普通列表控件。
- 详情/表单页用语义快照定位「保存」「提交」「添加」「删除」等按钮,以及输入框/选择框/数字输入等表单控件,断言页面加载完成。
- 进入详情后,如需读取最新数据,必须点击返回到列表页,再从列表重新进入详情;不要在已打开详情页假设数据自动刷新。
- 新增、编辑、删除、导入、导出或提交,只有用户明确要求该具体动作和目标数据时才执行;否则只验证页面可见性与只读流程。
- 以语义状态断言为主。只在进入目标页面、关键状态变化、失败或异常时截图,避免逐步截图。

## 截图规范

| 用途 | 路径 | 生命周期 |
| --- | --- | --- |
| 临时过程截图(排查 hover/click 失败、验证弹层内容) | `/tmp/vanchen-e2e-<task-space>-<seq>.png` | 报告写完后由主 agent 统一 `rm`,留出排错窗口 |
| 关键流程证据(进入成功的最终页面、唯一失败现场) | `<工作区绝对路径>/docs/e2e/screenshots/<task-space>/<菜单路径>.png` | 本地保留,作为可追溯证据；不提交 Git |

`ego-browser` 运行时的当前目录不保证是工作区根目录。调用 `captureScreenshot` 时必须传入工作区绝对路径；不要使用 `docs/e2e/...` 相对路径。

**清理命令**(在主 agent 输出报告后):

```bash
rm -f /tmp/vanchen-e2e-<task-space>-*.png
```

**本地命名示例**(混合方案:目录用中文 slug,文件名用拼音或 menu-index):

- `<工作区绝对路径>/docs/e2e/screenshots/random5/档案-供应商审核-审核模板.png`
- `<工作区绝对路径>/docs/e2e/screenshots/random5/m3-弹层未出现.png`(失败证据)
- `<工作区绝对路径>/docs/e2e/screenshots/random5/m4-店铺-食安主体责任制-食品安全自查.png`

**禁止**:

- 截图落在工作目录根或随意命名的位置
- 每个动作都逐步截图(违反"以语义状态断言为主")
- 把任何 e2e 截图 commit 到 git
- 关键流程证据没有截图就报告"通过"

## 并发

可将不同菜单分配给多个 agent 并行测试。每个 agent 使用独立 task space,并在结果中回传完整路径、实际断言和异常。

同一菜单可以并行执行导航、查询和详情查看。写操作必须由主 agent 分配唯一测试数据或串行执行;浏览器 space 不会隔离后端数据。

仅主 agent 修改 `docs/e2e/config.json`。缺少路径或页面菜单与索引不一致时,先用真实页面核对,再追加实际验证成功的完整层级和可复用的页面断言。

## API 调试(仅按需)

只有用户明确要求排查接口、请求或响应体时,才读取 `references/fsms-api-debug.md`。该参考只辅助解释真实 UI 操作,不得替代页面点击、状态断言或写操作授权。

## 输出

报告实际模块与完整菜单路径、已执行操作、状态断言结果,以及关键截图或失败证据。不要把未执行的动作或未验证的菜单称为通过。

对每个入口失败明确标记为"弹层未出现""菜单文本不匹配""页面接口/加载未完成"或"页面断言失败",不要笼统报告"进入失败"。

每条失败必须注明证据路径(临时截图 `/tmp/...` 或入库截图 `docs/e2e/screenshots/...`)。
