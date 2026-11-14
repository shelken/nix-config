# iphone 的设计

[scripts/iphone](./scripts/iphone) 是 [Pinky](https://github.com/DIYgod/pinky) MCP 的命令行薄封装。用法见 [SKILL.md](./SKILL.md)，首次配置与排障见 [references/setup.md](./references/setup.md)，端到端测试是 [tests/e2e.py](./tests/e2e.py)。本文记录术语、不变量和设计决策

## 术语与不变量

- **网关 (Gateway)**: Pinky 在本机运行的进程，持有手机连接，执行审批与规则。_避免_: 服务端、后端
- **租约 (Lease)**: 一个 MCP 会话对一台手机的占用，由 `iphone up` 建立、`iphone down` 释放
- **Helper**: iOS 27 以下装在手机上的 WebDriverAgent，Pinky 靠它点击和输入

不变量：

1. `iphone` 不做任何策略判断：审批、屏蔽 App、凭据拦截、只读模式都在网关
2. 一条子命令对应一个 `phone_*` 工具；工具返回的文本原样打印，不重新格式化
3. 退出码只看首行状态：`settled` 为 0，其余为 1。`find`、`wait` 另有「无命中」的 1
4. 不绕过网关：不直连 usbmuxd，不调用 adb、go-ios

## 依赖 Pinky MCP，不再自己管理 WDA

日期: 2026-11-08

原来的 `iphone` 自己下载官方 WDA Runner，用 Xcode 或 plumesign 签名安装，再经 usbmuxd 直连 WDA 读树发触控，约 2500 行。Pinky 已经提供同样的读屏与操作，并且多了网关强制的审批、屏蔽 App、凭据字段拦截、录像与历史。所以脚本改成 Pinky MCP 的客户端，以后跟随 Pinky 演进

### 后果

- 传输用 Streamable HTTP，会话 ID 存在 `$IPHONE_HOME/session`。每次命令是新进程，租约靠这个会话跨进程保留。会话 1 小时无请求过期，租约空闲 10 分钟结束
- 需要用户在 Pinky 里打开 设置 › 智能体 › 远程智能体（Settings › Agents › Remote agents）（默认关）。token 由 `Pinky token` 取，只在内存里用，不落盘
- 在 Pinky 看来这个会话是一个远程 agent，名字带 `(remote)`，首次连接要用户批准，不继承本机同名 agent 的权限
- 元素标识从 `tN` 变成 Pinky 的数字 `ref`；坐标单位从点变成截图像素
- 失去：iOS 17.4 以下、签名与安装链路（plumesign、rcodesign、SideStore、Xcode 选路）、`autolock`、中转快捷指令、结束 App、查询 App 运行状态
- iOS 27 以下的 helper 要用户自己用 Xcode 装，7 天重签一次（免费 Apple ID）。这是目前最大的退步，见下节
- 旧实现在 git 历史里（`modules/features/ai/skills/iphone-use-best-practice/scripts/iphone`，本次改动之前）

### 考虑过的替代方案

- **stdio 常驻桥接进程**：不用开远程智能体，但要自己管后台进程与本地 socket，代码更多
- **保留旧脚本作 `iphone-legacy`**：旧设备仍可用，但要维护两份
- **每条命令自动 `phone_connect`**：任务名没有来源，也会让「用户批准」的时机变得不可预期，所以只有 `up` 建立租约

## 上游 Pinky 目前的不足

对照旧脚本的实测经验整理，可以考虑提 PR。标「已实测」的是旧脚本在真机上跑过的结论，标「未验证」的是读代码得出、没有在 Pinky 上复现的

1. **不能安装或重签 helper（最大缺口）**。Pinky 的文档把「Installing and re-signing the helper from Pinky」列在 Not done yet，目前让用户在 Xcode 里手动 Product › Test。旧脚本已实测的做法：
   - 下载固定版本并校验 sha256 的官方 Runner（appium/WebDriverAgent 的 release zip），不用 Xcode 构建
   - 签名顺序：先 plumesign 签主 app 取得证书，再用 rcodesign 补签 `PlugIns/*.xctest`（plumesign 不签它，不补签设备会拒绝加载，Runner 随即退出），最后第二遍 plumesign 封整包
   - 用 `xcrun devicectl device install app` 安装
   - 装之前查免费描述文件的 3 个 App 名额（跨团队计数，iOS 硬限制），满了报出该卸哪个，不签完才发现装不上
   - 免费账号开发证书上限 2 个，plumesign 超限时不询问直接吊销别的工具的证书
2. **iOS 17.4 到 26 的启动方式未在真机验证**。Pinky 用 go-ios 的 testmanagerd 加自己的 tunnel 启动 helper，其文档写明「Nowhere」跑过。旧脚本已实测另一条路：`xcodebuild test-without-building -xctestrun <文件> -destination id=<UDID>` 启动手机上已装的 Runner，不需要 Xcode 登录 Apple ID，不需要 `-allowProvisioningUpdates`，也不需要 tunnel（iOS 27.2 实测）。可作为 testmanagerd 路径失败时的回退
3. **回主屏后立刻读树会卡死（未验证，Pinky 代码里没有对应处理）**。WDA 会去读刚被系统挂起的旧 App 的树，卡满约 60 秒才返回。旧脚本的做法：Home 之后轮询 `POST /session/<sid>/wda/apps/state` 直到旧 App 不再是前台（状态 4），再取树，实测约 0.9 秒、8 次 8 次不卡；不能用 `/wda/activeAppInfo` 做信号，它在这个窗口里会卡住（实测 2/8）。Pinky 的 `pressHome` 之后直接等画面稳定再读树，`/source` 超时是 30 秒，可能表现为 Home 后偶发的读屏失败
4. **看不到免费证书何时过期（未验证）**。Pinky 只在文案里说「7 天后要重签」。旧脚本读已装 App 的 `embedded.mobileprovision` 的 `ExpirationDate` 显示剩余天数。可以在 Settings › Phones 提前提醒，而不是等 helper 起不来
5. **WDA 路径没有遮挡过滤（未验证）**。Pinky 的 iOS 27 路径有 `unoccluded`，WDA 路径的 `wdaScreenElements` 没有。旧脚本实测：AX 树看不出遮挡，被悬浮搜索栏盖住的最后一行仍在树里，点它的中心会点进搜索栏；元素贴着屏幕底边（视口下方约 10%）时点击落进手势区被吞（iPhone 14 上必现）
6. **手机会自动锁屏**。Pinky 靠「用户用 Touch ID 从电脑解锁」应对，但任务中途锁屏仍会打断。旧脚本把自动锁定设为永不：WDA 直接打开 `prefs:` 会被系统拒绝（错误 115），只有「快捷指令」的「打开 URL」动作能打开 `prefs:root=DISPLAY&path=AUTOLOCK`
7. **session 能力项（未验证价值）**。旧脚本创建 session 时带 `shouldTerminateApp: false`、`waitForIdleTimeout: 0`、`maxTypingFrequency: 30`；Pinky 只传 `shouldWaitForQuiescence: false`，其余靠 appium settings
8. **应用范围只限制「打开和操作」，不限制「看」（已实测，iPhone 14）**。范围外的 App 用 `launch` 被拒，但在主屏点它的图标能打开，进去后 `tap`、`scroll` 被拒、读屏不被拒。原因是主屏属于系统界面，`policy.Evaluate` 对它一律放行，而读屏不经过策略。可行的改法：前台是范围外 App 时，`agentView`（`internal/gateway/pipeline.go`）像对待被屏蔽的 App 那样返回 `blocked app`
9. **任务白名单（`phone_connect` 的 `apps`）不过滤 `phone_apps`（已实测）**。只有 agent 范围会过滤，见 `internal/gateway/agent.go` 的 `phone_apps` 实现
10. **范围按显示名或 bundle id 完全匹配，显示名随手机语言变化（已实测）**。范围里写「设置」，英文界面的手机上它叫 `Settings`，匹配不上，`launch` 被拒。界面应提示优先填 bundle id
11. **iOS 27.0.1 上 displayservice 通道断开后，读屏正常、输入全部失败，Pinky 没有回退（已实测，iPhone 17）**。现象：`iphone snapshot` 成功，`tap`、`tap-text`、`home` 都返回 `uncertain`，错误为 `connect com.apple.coredevice.displayservice: ConnectToXpcServiceTunnelIface: failed to connect to http2: NewHttpConnection: could not read frame. EOF`。与前台 App 无关，重建租约无效，重新插拔 USB 后恢复。读屏走 accessibility，输入走 displayservice 加 HID，所以两者会一个正常、一个失效。同一台手机在旧 WDA 路径下输入一直正常，因此故障在 CoreDevice 通道，不在手机或线缆。根因未查明：故障出现在手机刚装好另一个使用 CoreDevice 的 App 并完成配对之后，相关性未证实。后续要处理：
    - displayservice 连续失败时，自动重建隧道，或回退到 WDA helper
    - 把「读屏成功、输入失败」报成专门状态。`uncertain` 让 agent 以为动作可能已发生，实际一次都没有执行
    - 临时绕过（未验证）：Pinky 的 Settings › Phones 里把该手机的连接改成 WebDriverAgent helper，见 [references/setup.md](./references/setup.md) 的「已知限制」
    - 复现：先确认 `iphone snapshot` 成功，再执行 `iphone home`，看首行状态

Pinky 做得比旧脚本好的地方：helper 启动时设 `USE_IP=127.0.0.1`，让 WDA 只监听手机回环，不暴露在 Wi-Fi 上；旧脚本的 xctestrun 没设它，WDA 监听所有接口。免费描述文件的「设备信任」与自动化授权口令提示（`enabling automation mode`）的检测也更完整

## Pinky 与 Swipt 的对比

日期: 2026-11-08，标「2026-11-15 复测」的行用 Pinky 2026.1115.1 重测。Swipt 是另一个控制 iPhone 的工具，`scripts/iphone` 不调用它；skill 里两者的分工见 SKILL.md 的「选通道」。以下在 iPhone 17（iOS 27）上实测，Swipt 为 0.1.0 (59)。除「没有 USB 时可用」一行外，2026-11-08 的测试手机插着 USB，Swipt 的 Mac 到手机链路始终是局域网 HTTP。判断是否插线用 `xcrun devicectl list devices --json-output <文件>` 里的 `transportType`（`wired` 或 `localNetwork`）；`iphone status` 的 CONNECTION 列显示 Pinky 实际用的连接（`usb` 或 `wifi`）

图例

- ✅ 已实测可用
- ❌ 已实测不可用，或实测没有这层保护
- ⚠️ 可用但有限制，见备注
- ➖ 没有这个功能，读文档或代码得出
- ❓ 没测，原因在备注

### 连接

| 项目 | Pinky | Swipt | 备注 |
|---|---|---|---|
| 没有 USB 时可用 | ✅ | ✅ | 2026-11-15 复测：`transportType` 为 `localNetwork` 时，Pinky 的 `up`、`snapshot`、`launch`、`type` 照常成功。Pinky 从 2026.1113.17 起默认经 Wi-Fi 连接，要求手机与 Mac 同一网络；Wi-Fi 下锁屏的手机返回 `device_needs_setup` 等用户解锁 |
| 空闲后自动重连 | ✅ | ✅ | 2026-11-15：Swipt 的「已停止」是连接空闲（源码 `internal/device/connection.go`，没有调用者时超时断开），下一次调用自动重连；空闲后的第一次调用实测报过一次 `ECONNRESET`，重试成功 |
| 两者同时连着互不影响（插着 USB） | ✅ | ✅ | Pinky 租约保持，两边交替截图、读树、回主屏、点击，3 轮共 24 次调用全部成功，没有复现上文第 11 条 |
| 需要在手机上侧载 App | ➖ | ✅ | Swipt 要侧载并续期。Pinky 在 iOS 27 上是否需要 helper 未单独验证 |

### 读界面

| 项目 | Pinky | Swipt | 备注 |
|---|---|---|---|
| 读原生 App 界面 | ✅ | ✅ | 主屏、设置、Safari 外壳都能读 |
| 读网页里的输入框 | ✅ | ✅ | 2026-11-15 复测：Pinky 给出带 ref 的 `input ... editable`，密码框另带 `password`（DIYgod/pinky#4，2026.1108.21 起）；Swipt 给出 `textField`、`webContent` 和 `secure` 标记 |
| 屏幕文字识别 | ✅ | ✅ | Pinky 是 `ocr` 行；Swipt 用 `screen.find`，中文不要传 `languages`，传了找不到 |
| 按文字查找 | ✅ | ⚠️ | Swipt 的 `accessibility.find` 在 Safari 页面上找不到元素，改用 `snapshot().find` 才命中 |
| 截图 | ✅ | ✅ | Pinky 存 JPEG；Swipt 存 PNG，能写到手机文件再拉回 Mac |
| 等待文字出现 | ✅ | ➖ | Swipt 只有等画面稳定、等变化，没有按文字等待 |
| 等待画面稳定 | ❓ | ✅ | Pinky 每个动作自带稳定检测，没有单独命令 |

### 操作

| 项目 | Pinky | Swipt | 备注 |
|---|---|---|---|
| 点元素 | ✅ | ✅ | |
| 点坐标 | ✅ | ✅ | Pinky 用截图像素，Swipt 用点 |
| 按文字点击 | ✅ | ➖ | Swipt 要自己组合 `find` 与 `tap` |
| 输入文字到原生输入框 | ✅ | ✅ | |
| 输入文字到网页输入框 | ✅ | ✅ | 2026-11-15 复测：Pinky 先 `tap <ref>` 再不带 `--ref` 输入；直接 `type --ref` 返回 `uncertain`，输入框没拿到焦点 |
| 滑动或滚动 | ✅ | ✅ | |
| 拖拽 | ✅ | ❓ | Swipt 只测了 `swipe` 与 `touch` |
| 多指手势 | ➖ | ✅ | `input.pinch`、`input.touch` |
| 回车键 | ✅ | ✅ | |
| 回主屏 | ✅ | ✅ | |
| 打开应用切换器 | ❓ | ✅ | |
| 电源键、音量键 | ❓ | ❓ | 会锁屏或改音量，没测 |

### App

| 项目 | Pinky | Swipt | 备注 |
|---|---|---|---|
| 按 bundle id 启动 | ✅ | ✅ | |
| 按显示名启动 | ❓ | ➖ | Pinky 文档支持，本轮只用了 bundle id |
| 用 URL 打开链接 | ✅ | ✅ | 2026-11-15 复测：`iphone launch https://…` 在 Safari 打开该页（DIYgod/pinky#3，2026.1108.21 起）；Swipt 用 `launchApplication(id, {url})` |
| 强制重启式启动 | ➖ | ✅ | `restart: true` |
| 列出已装 App | ✅ | ✅ | Swipt 返回 310 个，带版本 |
| App 前后台事件 | ➖ | ✅ | `device.applicationEvents` |

### 手机侧能力

| 项目 | Pinky | Swipt | 备注 |
|---|---|---|---|
| 手机发起 HTTP 请求 | ➖ | ✅ | `fetch`，出口是手机的网络 |
| 手机本地文件读写 | ➖ | ✅ | |
| 手机文件拉到 Mac，Mac 文件推到手机 | ➖ | ✅ | `swipt repl data read`、`write` |
| SQLite | ➖ | ✅ | |
| 录屏 | ❓ | ✅ | Swipt 录 2 秒，返回时长与帧事件；Pinky 文档称有录像，未测 |
| 常驻自动化（Swiplet） | ➖ | ✅ | 只验证了 `swiplet list`，当前没有安装 |
| 读剪贴板 | ❓ | ❌ | 系统拒绝：条目含受保护内容 |
| 写剪贴板 | ❓ | ❓ | 会覆盖你的剪贴板，没测 |
| 自动解锁 | ❓ | ❓ | 要先在 Swipt 保存锁屏密码，没测 |

### 安全与管控

| 项目 | Pinky | Swipt | 备注 |
|---|---|---|---|
| 敏感动作需要用户批准 | ❓ | ❌ | Swipt 全程无任何请示；Pinky 没找到安全的触发场景 |
| 限定可用 App | ✅ | ❌ | Pinky 对范围外 App 返回 `scope_denied`；Swipt 能启动任意 App |
| 只读模式 | ⚠️ | ❌ | Pinky 只读下点击、启动、回主屏仍然通过，只拦会请示的动作 |
| 拦截网页密码框输入 | ❌ | ❌ | 两者都把假数据写进了网页密码框，Swipt 能看到 `secure` 标记但不拦 |
| 拦截原生密码框输入 | ❓ | ❓ | 没找到安全的测试页面 |
| 请用户接管、提问 | ❓ | ❓ | 要用户在手机或 Pinky 上操作，没测 |

### 结论

- 界面操作两者都能完成，包括 URL 打开、网页输入框和不插 USB；差别在管控：只有 Pinky 有范围限制与请示，且两者都没拦网页密码框
- Swipt 的独有能力集中在手机侧：HTTP、文件、SQLite、前后台事件、录屏、多指手势、Swiplet
- 所以两者平级：要范围限制或请示的操作走 Pinky，手机侧能力走 Swipt，其余看哪边已连上
- 同时连着没有冲突，但同一块屏幕仍建议一次只由一边驱动

### 复现

```bash
iphone up --task "对比测试" && iphone snapshot && iphone down --summary "完成"
swipt device list
swipt repl api                                  # Swipt 可用的全部 JS 接口
swipt repl run 'await device.info()'
swipt repl run 'return (await accessibility.snapshot({full:true})).findAll({secure:true}).length'
```

## 运行时目录

根目录是 `~/.local/share/iphone-use/`，`IPHONE_HOME` 可改。只剩两项：`session`（MCP 会话 ID）和 `shots/`（最近 20 张截图）。旧实现留下的 `config.json`、`cli/`、`artifacts/`、`xcode/` 可以删除
