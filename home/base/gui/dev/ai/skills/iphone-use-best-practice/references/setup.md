# 首次配置与排障

## 首次配置

前提：完整 Xcode（已同意许可 `sudo xcodebuild -license accept`、`sudo xcodebuild -runFirstLaunch`）；Xcode → Settings → Accounts 已登录 Apple ID；iPhone 开启开发者模式，USB 连接、解锁并信任此电脑。以上由用户本人完成。

```bash
iphone init --team <TeamID> --bundle <全局唯一的 bundle id>
iphone renew     # 首次构建较慢
iphone up
```

- `--team`：Xcode 账号里个人团队的 Team ID（`security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject` 的 `OU=`）。
- 首次 `up` 后，手机上要到「设置 → 通用 → VPN 与设备管理 → 开发者 App」信任该证书，再重新 `iphone up`。
- 配置和构建都在 `~/.local/share/iphone-use/`（`IPHONE_HOME` 可改）。

## 常见报错

| 现象 | 原因与处理 |
|---|---|
| `手机锁屏，等待用户解锁` | `up` 会继续等；用户解锁后自动继续 |
| `手机没信任开发者证书` | 用户在手机上信任，再 `iphone up` |
| `Xcode 的 Apple ID 登录失效` | 只能用户打开 Xcode → Settings → Accounts 重新登录一次；命令行无法登录 |
| `签名证书或描述文件缺失` | `iphone renew`；仍失败看 `~/.local/share/iphone-use/cli/build.log` |
| `WDA 未运行` | `iphone up` |
| `WDA 在运行，但不是本 CLI 启动的` | 别的工具启动了它；先停掉那个工具 |
| `快照已过期` | 前台 App 变了；重新 `iphone snapshot` |
| 启动 120 秒仍不就绪 | 看 `~/.local/share/iphone-use/cli/up.log` |

## 已知限制

- 免费账号证书 7 天过期。过期后 `iphone up` 自动重签并重装。
- 免费账号最多同时装 3 个开发 App。
- `launch` 只认 bundle id。`xcrun devicectl device info apps` 实测只列出 5 个开发者签名的 App，不含 App Store 的 App，所以 CLI 不提供按名称启动。
- 自绘界面、部分游戏的 AX 树为空，用 `shot` 加坐标点击。
- WDA 直接打开 `prefs:` / `settings-navigation:` 会被系统拒绝（iOS 27.0.1，`LSApplicationWorkspaceErrorDomain 115`）；`App-prefs:` 带页面路径会落到「App」页。但快捷指令的「打开 URL」动作能打开 `prefs:root=DISPLAY&path=AUTOLOCK`，WDA 又能打开 `shortcuts://run-shortcut?name=…`，所以经快捷指令可一步直达任意设置页。

## 中转快捷指令（prefs: 与自动锁定用）

WDA 直接打开 `prefs:` 会被系统拒绝，只有「快捷指令」里的「打开 URL」能打开。`iphone open <url>` 先直接打开，被拒（115）时转给中转快捷指令；`iphone autolock`、`up`、`down` 也靠它一步直达自动锁定页（约 6 秒，没有时走界面点击约 13 秒）。

```bash
iphone setup-shortcut            # 默认名 iphone-open-url，--name 可改
```

它在 Mac 上生成并签名只含「打开 URL」（输入取「快捷指令输入」）的快捷指令，后台导入并用 `computer-use` 点掉确认框，写入配置 `open_url_shortcut`，等 iCloud 同步到手机后用 `prefs:root=BATTERY_USAGE` 实测。

- 需要：macOS 的 `shortcuts` 与 `computer-use` 命令、Mac 与手机同一 iCloud 且开启「快捷指令」同步、WDA 在运行（否则只导入不实测）。
- 同名已存在会拒绝，避免得到「iphone-open-url 1」；先在快捷指令里删掉。
- 手机上首次运行可能弹授权提示。命令会把弹窗文字打印出来并最多等 60 秒，需要用户本人在手机上批准。
- `iphone init` 会重写 `config.json`，之后重新运行 `iphone setup-shortcut` 或手动补回 `open_url_shortcut`。
