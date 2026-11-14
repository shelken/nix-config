# 首次配置与排障

`iphone` 依赖本机的 Pinky。下面的步骤都由用户本人完成；Agent 不代做 Apple ID 登录、密码、验证码。

## 首次配置

1. 安装 Pinky 并打开（macOS 12 及以上）。`iphone` 在 `PINKY_BIN`、PATH 里的 `pinkyctl`、`/Applications/Pinky.app`、`~/Applications/Pinky.app` 里按序找它
2. iPhone 首次用 USB 连接、解锁、信任此电脑。Pinky 的 Add phone 页会检查开发者模式与开发者磁盘镜像，缺什么它会说。之后手机与 Mac 在同一网络时，不插线也能用（Pinky 的 Settings › Phones › Use iPhones and iPads over Wi-Fi，默认开）
3. 在 Pinky 的 设置 › 智能体 › 远程智能体（Settings › Agents › Remote agents）打开开关「允许智能体通过 HTTP 连接」，`iphone` 才能连上它的 HTTP 端点（默认 `http://127.0.0.1:7465/mcp`）
4. `iphone status` 确认手机在列表里、HTTP 可达，再 `iphone up`。首次连接要用户在 Pinky 里批准这个远程 agent，并选范围

### 限定可用的 App（推荐）

首次批准 `iphone (remote)` 时默认是「除已屏蔽应用外的所有应用」。想限制，在 Pinky 的 设置 › 智能体 里把它改成「仅限我选择的应用」并填白名单，改完对正在运行的会话立即生效。

- 填 **bundle id**（如 `com.apple.Preferences`），不要填显示名：显示名随手机语言变化，英文界面的「设置」叫 `Settings`，对不上
- 查 bundle id，不连手机：`curl -s "https://itunes.apple.com/search?term=关键词&entity=software&country=cn&limit=5"`，看结果里的 `bundleId`；只覆盖 App Store 上架的 App
- 范围只限制**打开和操作**，不限制**读屏**：在主屏点图标仍能进入范围外的 App 并读到内容，之后 `tap`、`scroll` 才会被拒。要让某个 App 完全不可见，把它加进 Pinky 设置 › 安全 的屏蔽列表

### iOS 27 及以上

手机上不用装任何东西。Pinky 用 CoreDevice 的屏幕流与触控。首次要 Xcode 在手机连着时打开一次，让开发者磁盘镜像挂上，之后它会一直在。

### iOS 17.4 到 26

没有 helper 时只能读屏和开 App，`tap`、`type`、`scroll`、`key` 返回 `unsupported`。要装 WebDriverAgent helper，由用户在有 Xcode 的 Mac 上做一次：

1. `git clone https://github.com/appium/WebDriverAgent`
2. 打开 `WebDriverAgent.xcodeproj`，在 WebDriverAgentRunner target 的 Signing & Capabilities 里选 Team（免费 Apple ID 可以）。若提示 bundle id 被占用，改前缀（`com.<你>.WebDriverAgentRunner`），名字里保留 `WebDriverAgentRunner`，Pinky 靠它找到 helper
3. 选这台 iPhone 作目的地，Product › Test 跑一次；手机若提示信任开发者，到「设置 › 通用 › VPN 与设备管理」信任。Xcode 日志出现 `ServerURLHere` 后停止测试

之后 Pinky 每次打开手机都会自己启动 helper。免费 Apple ID 的签名 7 天过期，过期后重复第 3 步。更多细节见 Pinky 仓库的 `docs/notes/ios.md`。

iOS 17.3 及以下不支持。

## 运行时

| 位置 | 内容 |
|---|---|
| `~/.local/share/iphone-use/session` | MCP 会话 ID，`up` 创建、`down` 删除 |
| `~/.local/share/iphone-use/shots/` | `iphone shot` 的最近 20 张截图 |

`IPHONE_HOME` 改根目录；`IPHONE_PINKY_URL` 改端点；`PINKY_BIN`、`PINKY_TOKEN` 分别指定 Pinky 可执行文件与 token。

## 常见报错

| 现象 | 原因与处理 |
|---|---|
| `找不到 Pinky` | 安装 Pinky，或设 `PINKY_BIN` |
| `连不上 Pinky 的 HTTP 端点` | 打开 Pinky，设置 › 智能体 › 远程智能体（Settings › Agents › Remote agents） 开启 |
| `Pinky 拒绝了 token` | token 被重置；去掉过期的 `PINKY_TOKEN` 环境变量 |
| `没有会话。先运行 iphone up` | 还没 `up`，或 `down` 之后 |
| `会话已过期` | 1 小时没请求。`iphone up` |
| `No phone is connected in this session` | 租约空闲 10 分钟已结束。`iphone up` |
| `approval_pending` | 用户还在 Pinky 里决定。用 `--approval-id` 原样重发 |
| `lease_held` | 别的 agent 在用这台手机，结果里写了是谁 |
| `device_offline` | 手机没插线，也不在 Mac 所在的网络。重启后的 iPhone 要用户解锁一次；租约在断线 60 秒内保留 |
| `device_needs_setup` | 手机在等用户做一步，返回说明里写了是哪一步：Wi-Fi 下锁屏时要解锁；Mac 的设备服务（usbmuxd）丢了手机时要重启它，Pinky 会提示 |
| `device_locked` | `iphone handoff "请解锁手机"` |
| `unsupported` 且提到 helper | iOS 27 以下没装 helper，见上 |
| `blocked_by_policy` 的 `credentials` | 密码和验证码字段只能用户本人输入，用 `handoff` |

## 已知限制

- 经 Wi-Fi 比 USB 慢，截图要几秒，视频偶尔丢帧；插着线时 Pinky 走 USB
- iPhone 的屏幕流开着时，部分银行 App 会警告或拒绝运行；Pinky 在手机页打开、agent 工作时与之后 30 秒会开流。需要用这类 App 时在 Pinky 的 Settings › Phones 把该手机的连接改成 WebDriverAgent helper
- 通过 helper 读一次主屏约 7 秒，点击 0.5 到 0.8 秒；iOS 27 的 CoreDevice 路径读屏不到 0.5 秒
- 用 helper 时，iOS 偶尔会在手机上要密码来允许自动化，此时 Pinky 会提示用户在手机上输入
