# iphone 的设计

[scripts/iphone](./scripts/iphone) 是 [Pinky](https://github.com/DIYgod/pinky) MCP 的命令行薄封装，不做策略判断、不绕过网关。日常用法见 [SKILL.md](./SKILL.md)，首次配置与排障见 [references/setup.md](./references/setup.md)，端到端测试见 [tests/e2e.py](./tests/e2e.py)

## 依赖 Pinky MCP，不再自己管理 WDA

日期：2026-11-08

旧实现自行下载签名 WDA Runner 并直连 usbmuxd，约 2500 行。Pinky 已提供同类读屏与触控，并补齐网关级审批、屏蔽 App、凭据拦截与历史记录，因此改为 Pinky MCP 客户端跟随上游演进

设计取舍与关键后果：

- 采用 Streamable HTTP 并在 `$IPHONE_HOME/session` 保存会话 ID，使每次独立运行的 CLI 进程共享同一租约（会话空闲 1 小时过期、租约 10 分钟结束）；token 经 `Pinky token` 动态获取不落盘
- 放弃常驻 stdio 桥接（多一层后台进程与本地 socket 管理）、放弃保留 `iphone-legacy`（维护两份实现）、放弃每条命令自动 `phone_connect`（缺少任务名来源且审批时机不可预期）
- 升级后 `~/.local/share/iphone-use/`（或 `$IPHONE_HOME`）里旧实现遗留的 `config.json`、`cli/`、`artifacts/`、`xcode/` 可直接删除

## 上游 Pinky 的主要限制

以下限制仍直接影响日常使用：

- **无法自动安装或重签 helper**：iOS 27 以下仍需在 Xcode 中手动 `Product › Test`，免费 Apple ID 每 7 天重签一次且无过期提醒
- **应用范围只拦操作不拦读屏**：主屏打开范围外 App 后虽拦截触控，但读屏不经策略检查；范围按显示名匹配随系统语言变化，建议统一填 bundle id
- **任务白名单不过滤 `phone_apps`**：仅 agent 级范围过滤已装 App 列表，`phone_connect` 的 `apps` 白名单不生效
- **iOS 27 的 CoreDevice displayservice 断连无回退**：实测可能出现读屏正常而 `tap`/`home` 全部返回 `uncertain`（隧道 EOF），重建租约无效，需重插 USB 或在 Pinky 设置中临时切回 WDA helper

## Pinky 与 Swipt 的对比

以下基于 2026-11-08 与 2026-11-15 在 iPhone 17（iOS 27）上对 Pinky 与 Swipt 的实测结论，通道选择规则见 [SKILL.md](./SKILL.md)

### 结论

- 界面操作两者都能完成，包括 URL 打开、网页输入框与不插 USB；核心差异在管控：只有 Pinky 有范围限制与请示，且两者目前都未拦截网页密码框输入
- Swipt 的独有能力集中在手机侧：HTTP 请求、文件读写、SQLite、前后台事件、录屏、多指手势、剪贴板、电源与音量键、Swiplet
- Swipt 保存锁屏密码后可自行解锁手机，且没有任何审批请示，拿到其 API 即可完整操作设备
- 两者平级互补：需要范围限制或审批走 Pinky，需要手机侧能力走 Swipt，其余看哪边已连接；同时在线无冲突，但同一屏幕一次只由一边驱动

### 复现

```bash
iphone up --task "对比测试" && iphone snapshot && iphone down --summary "完成"
swipt device list
swipt repl api                                  # Swipt 可用的全部 JS 接口
swipt repl run 'await device.info()'
swipt repl run 'return (await accessibility.snapshot({full:true})).findAll({secure:true}).length'
```
