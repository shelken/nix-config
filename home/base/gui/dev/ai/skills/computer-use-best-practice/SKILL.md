---
name: computer-use-best-practice
description: 当需要在 macOS 后台启动 GUI 应用且防止抢焦点、或希望自动化操作不打扰用户当前工作时阅读该技能
---

## Rules

- 仅适用于 macOS（依赖 `NSWorkspace` 焦点通知 API）
- `didActivateApplicationNotification` 不区分激活来源（用户点击 vs app 调 activate），因此 guard 必须用 `--target <name>` 指定会抢焦点的目标 app，只拦截目标，放行用户主动切换；不指定 target 会误拦截用户切窗口
- 启动会抢焦点的 GUI 应用前，先用 `focus-guard <seconds> --target <AppName> &` 武装焦点保护，再启动目标应用；guard 在指定秒数内拦截目标的抢焦点行为并切回原前台
- 保护时长需覆盖目标应用的抢焦点窗口（冷启动 + 初始化，通常 15-20s 足够）；目标应用稳定后再结束 guard
- guard 无侵入：不注入、不 hook、不改目标应用，仅在系统焦点通知上做反向切换，对任何 app（Electron / native / Java）同等有效
- 入口在本技能 `bin/focus-guard` 启动器，调用前解析为绝对路径；首次使用自动编译到 `~/.cache/computer-use/`（约 30s，仅一次），编译失败提示 `xcode-select --install`
- guard 退出后失去保护；如目标应用可能在更晚抢焦点，按需延长保护时长或重启 guard

### 焦点保镖调用链路

1. 解析启动器绝对路径：`<skill-dir>/bin/focus-guard`
2. `focus-guard <seconds> --target <AppName> &` — 后台启动，记录当前前台并订阅焦点通知
3. 启动目标应用（`open -a` / spawn / 其它）
4. 目标应用抢焦点 → guard 收到 `didActivateApplicationNotification` → 匹配 target → 立即 `activate` 切回原前台
5. `<seconds>` 到期或 `kill %1` → guard 退出，保护结束
