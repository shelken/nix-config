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

WDA 直接打开 `prefs:` 会被系统拒绝，只有「快捷指令」里的「打开 URL」能打开。`iphone open <url>` 先直接打开，被拒（115）时转给中转快捷指令；`iphone autolock`、`up`、`down` 也靠它一步直达自动锁定页（约 6 秒）。

```bash
iphone setup-shortcut            # 默认名 iphone-open-url，--name 可改
```

快捷指令靠 iCloud 同步，所以**按设备记录**：配置 `relay_devices` 列出能用它的手机 UDID，当前 `udid` 不在其中就不走中转，`autolock` 直接走界面点击（设置 → 显示与亮度 → 自动锁定，约 20 秒）。与 Mac 不同 iCloud 的手机属于这一类，无需也无法配置。中转失败时 `autolock` 同样自动回退到界面点击；`up` 里设置自动锁定失败只警告，不让已就绪的 `up` 失败。

`setup-shortcut` 在 Mac 上生成并签名只含「打开 URL」（输入取「快捷指令输入」）的快捷指令，后台导入并用 `computer-use` 点掉确认框，然后在**当前手机**上用 `prefs:root=BATTERY_USAGE` 实测；通过后才写入 `open_url_shortcut` 与 `relay_devices`。

- 需要：macOS 的 `shortcuts` 与 `computer-use` 命令、Mac 与手机同一 iCloud 且开启「快捷指令」同步、WDA 在运行（否则只导入不实测）。
- Mac 上已有同名快捷指令时不重复导入，只在当前手机上实测并登记；换到另一台同 iCloud 的手机，直接再跑一次即可。
- 手机上首次运行可能弹授权提示。命令会把弹窗文字打印出来并最多等 60 秒，需要用户本人在手机上批准。
- `iphone init` 会重写 `config.json`，之后重新运行 `iphone setup-shortcut` 或手动补回 `open_url_shortcut` 与 `relay_devices`。

## 界面点击路径的坑

- 设置 App 重开会恢复上次的滚动位置，快照里的坐标是列表还在动时的；`_poll_node` 要求坐标连续两次一致才点。
- 目标行贴着屏幕底边时，点击中心落进底部手势区，点击被吞（iPhone 14 上「显示与亮度」在 y=807/844 时必现）；`_find_scrolling` 要求节点完整落在视口 8%~90% 内才点。
- 找不到时先向下滚，到头再掉头向上。
