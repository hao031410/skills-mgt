# ego-browser API 速查(FSMS E2E 实测版)

> 本文档基于 2026-07-16 在测试环境执行 5 个 FSMS 食品安全菜单的实测经验。
> 覆盖 `ego-browser nodejs <<'EOF' ... EOF` heredoc 模式下,所有浏览器操作的可用 facade、
> 参数类型、常见错误与最小模板。SKILL.md 里的旧示例假定的是 `page.xxx` / `browser.xxx` /
> `taskSpaces.xxx` 全局预加载的写法,但本模式下所有 helper 只在 `ego.helpers.*` 下。

## 1. facade 速查表

| SKILL 旧写法(不工作)        | 实际写法(实测可用)                          | 用途 |
| --------------------------- | ------------------------------------------ | ---- |
| `taskSpaces.useOrCreate(x)` | `ego.helpers.useOrCreateTaskSpace(x)`       | 创建/复用 task space |
| `taskSpaces.complete(x)`    | `ego.helpers.completeTaskSpace(x, opts)`    | 关闭 task space |
| `taskSpaces.handOff(x)`     | `ego.helpers.handOffTaskSpace(x)`           | 把控制权交还用户 |
| `taskSpaces.takeOver(x)`    | `ego.helpers.takeOverTaskSpace(x)`          | 用户授权后取回控制 |
| `taskSpaces.list()`         | `ego.helpers.listTaskSpaces()`              | 列出所有 task space |
| `taskSpaces.waitForAgentControl(x)` | `ego.helpers.waitForAgentControl(x)` | 等待用户在浏览器中完成操作 |
| `browser.openOrReuseTab(u)` | `ego.helpers.openOrReuseTab(u, opts)`       | 打开或复用 URL 的 tab |
| `browser.listTabs()`        | `ego.helpers.listTabs()`                    | 列出当前 tab |
| `browser.closeTab(id?)`     | `ego.helpers.closeTab(id?)`                 | 关闭指定 tab |
| `browser.ensureRealTab()`   | `ego.helpers.ensureRealTab()`               | 切换到非内部 tab |
| `page.goto(u)`              | `ego.helpers.gotoAndWait(u, opts)`          | 当前 tab 跳转 |
| `page.snapshot()`           | `ego.helpers.snapshot()`                    | 语义快照(含 refs) |
| `page.snapshotText()`       | `ego.helpers.snapshotText()`                | 纯文本快照(可直接 `slice`) |
| `page.screenshot()`         | `ego.helpers.captureScreenshot(filename)`   | 视口截图 |
| `page.evaluate(fn)`         | `ego.helpers.js(fn)`                        | 浏览器侧求值 |
| `page.locator(s).hover()`   | `ego.helpers.hover(selOrCoord)`             | hover 目标 |
| `page.locator(s).click()`   | `ego.helpers.click(selOrCoord)`             | 点击目标 |
| `page.mouse.move(x,y)`      | `ego.helpers.hover([x, y])`                 | 真实鼠标移动 |
| `page.waitForLoadState`     | `ego.helpers.waitForLoad(state, opts)`      | 等待 load state |
| `page.waitForNetworkIdle`   | `ego.helpers.waitForNetworkIdle({timeout})` | 等待网络空闲 |
| `page.waitForTimeout(ms)`   | `ego.helpers.wait(seconds)`                 | **单位是秒,不是毫秒** |
| `page.mouse.wheel(dx, dy)`  | `ego.helpers.scrollBy(dx, dy)`              | 鼠标滚轮 |
| `page.fill()` / `getByRole().fill()` | (本期无对应,优先用 JS + dispatchEvent 兜底) | 表单填写 |
| `page.setDefaultTimeout(ms)` | (无对应,每个调用单独传 timeout) | — |

## 2. target 接受形式

`hover` / `click` / 元素选择器 接受以下形式:

- **CSS selector**: `"button.primary"`、`"#search"`
- **`@N` / `ref=N`**: snapshot 输出的语义 ref,**只对同一 heredoc 内的最新 snapshot 有效**
- **`loc=...`**: snapshot 输出里的稳定选择器,如 `loc=css:input[placeholder="开始日期"]`
- **`[x, y]` 数组 / `{x, y}` 对象**: 视口坐标(像素)
- **`{selector, x, y}`**: 相对元素左上角的偏移

`captureScreenshot` 只接受 **字符串路径**(如 `/tmp/vanchen-m1.png`),不支持 `{ path: '...' }` 对象。

**不接受**:
- Playwright 的 `text=...` 字符串(报错 `Invalid selector: text=...`)
- `getByRole` / `getByLabel` / `getByPlaceholder` 等 Playwright 语义 helper(目前 facade 未暴露)

## 3. 返回结构

| helper | 返回类型 | 备注 |
|---|---|---|
| `snapshot()` | `{ content: string, refs: object }` | **不是字符串**,要 `.content` 才能 split |
| `snapshotText()` | `string` | 可直接 `.slice()` |
| `js(fn)` | 浏览器侧求值结果 | 直接用,不要 `JSON.parse` |
| `pageInfo()` | `{ url, title, w, h, sx, sy, pw, ph }` 或 `{ dialog }` | 原生对话框时返回 `dialog` 字段 |
| `listTabs()` / `listTaskSpaces()` | `Array` | 元素是对象 |

## 4. 常见错误(踩过的坑)

| 错误现象 | 原因 | 正确写法 |
|---|---|---|
| `ReferenceError: taskSpaces is not defined` | helper 不在全局 | `ego.helpers.useOrCreateTaskSpace(...)` |
| `Unknown helper: snapshot` / `browser` / `click` | 同上 | `ego.helpers.xxx` |
| `ElementResolutionError: Invalid selector: text=档案` | `hover` 不接受 `text=...` | 用 JS 动态取坐标 + `[x, y]` |
| `The "path" argument must be of type string ... Received an instance of Object` | `captureScreenshot` 不接受对象 | `captureScreenshot('/tmp/x.png')` |
| `TypeError: snap.split is not a function` | `snapshot()` 返回对象不是字符串 | `snap.content.split(...)` |
| `Unknown ref @N` | 跨 heredoc 复用 ref | 每个 heredoc 内重新 snapshot |
| 弹层误命中 `<html>` 根节点 | 用文本包含搜索定位弹层 | 按 className `menu_detail_container___2_08m` 锚定 |

## 5. 最小 heredoc 模板

```js
const task = await ego.helpers.useOrCreateTaskSpace('vanchen-e2e-<task-name>')
await ego.helpers.openOrReuseTab(ENV_URL, { wait: true, timeout: 30000 })
await ego.helpers.waitForLoad('networkidle', { timeout: 30000 })
await ego.helpers.wait(2)                 // 单位秒,用于视觉稳定

// === hover 一级菜单(动态坐标) ===
const navPoint = await ego.helpers.js(`(() => {
  for (const name of ['看板','档案','供应链','仓储','店铺','合规','数据']) {
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

// 关闭旧弹层(真实鼠标移动,不是合成 mousemove 事件)
await ego.helpers.hover([800, 600])
await ego.helpers.wait(1)

// hover + 等弹层稳定 + 找子菜单坐标 + click(原子动作)
await ego.helpers.hover([navPoint.x, navPoint.y])
await ego.helpers.wait(3)
const target = await ego.helpers.js(`(() => {
  for (const el of document.querySelectorAll('div')) {
    if (!(el.className || '').toString().includes('menu_detail_container')) continue;
    const r = el.getBoundingClientRect();
    if (r.width < 200) continue;
    if (el.closest('.menu_container___1zSTm')) continue;  // 排除侧栏本体内嵌的同名元素
    if (window.getComputedStyle(el).display === 'none') continue;
    for (const n of el.querySelectorAll('div, span')) {
      if ((n.textContent || '').trim() === 'TARGET') {
        const nr = n.getBoundingClientRect();
        if (nr.width > 0 && nr.height > 0) return { x: nr.left + nr.width/2, y: nr.top + nr.height/2 };
      }
    }
  }
  return null;
})()`)
if (!target) throw new Error('弹层未出现或菜单文本不匹配')

await ego.helpers.hover([target.x, target.y])
await ego.helpers.click([target.x, target.y])
await ego.helpers.waitForNetworkIdle({ timeout: 30 })
await ego.helpers.wait(2)

// 此后才允许 snapshotText / captureScreenshot

// === 任务结束 ===
await ego.helpers.completeTaskSpace('vanchen-e2e-<task-name>', { keep: false })
```

## 6. 推荐做法 vs 反模式

### ✅ 推荐

- **菜单阶段用 JS 动态取坐标**,不在 snapshot ref 上 hover/click
- **菜单阶段不在两次 hover/click 之间插入 `captureScreenshot` / `snapshotText` / `cliLog`**,会让鼠标离开弹层
- **每个 task space 对应一个用户目标**,不要为每个菜单新建 space
- **临时截图放 `/tmp`**,任务结束 `completeTaskSpace({ keep: false })` 后由主 agent 统一清理
- **关键证据截图放 `docs/e2e/screenshots/<task-space>/`**,入库保留

### ❌ 反模式

- 跨 heredoc 复用 `@N` ref
- 用 `taskSpaces.xxx` / `page.xxx` 全局调用
- 用 `text=...` 选择器
- `captureScreenshot({ path: ... })` 对象参数
- 用合成 `MouseEvent('mousemove')` 关闭旧弹层(可能不触发 React handler)
- 把每个动作都逐步截图(违反"语义状态断言为主")

## 7. 时间单位

| helper | 单位 |
|---|---|
| `wait(ms)` | **秒**(注意:Playwright 是毫秒) |
| `waitForLoad(state, opts)` | 毫秒 |
| `waitForNetworkIdle({ timeout })` | **秒** |
| `openOrReuseTab(u, { timeout })` | 毫秒 |
| `gotoAndWait(u, { timeout })` | 毫秒 |

## 8. 相关文档

- `SKILL.md` — 主 skill 文档,讲"做什么"
- `references/fsms-api-debug.md` — 排查接口/响应体时使用
- `assets/config.json.template` — `docs/e2e/config.json` 模板