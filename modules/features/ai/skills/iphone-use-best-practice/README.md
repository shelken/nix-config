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

Pinky 做得比旧脚本好的地方：helper 启动时设 `USE_IP=127.0.0.1`，让 WDA 只监听手机回环，不暴露在 Wi-Fi 上；旧脚本的 xctestrun 没设它，WDA 监听所有接口。免费描述文件的「设备信任」与自动化授权口令提示（`enabling automation mode`）的检测也更完整

## 运行时目录

根目录是 `~/.local/share/iphone-use/`，`IPHONE_HOME` 可改。只剩两项：`session`（MCP 会话 ID）和 `shots/`（最近 20 张截图）。旧实现留下的 `config.json`、`cli/`、`artifacts/`、`xcode/` 可以删除
