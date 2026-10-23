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

### 中转快捷指令（每台手机装一次）

WDA 直接打开 `prefs:` 会被系统拒绝，只有「快捷指令」里的「打开 URL」能打开。`iphone open <url>` 先直接打开，被拒（115）时转给中转快捷指令；`autolock`、`up`、`down` 靠它一步直达自动锁定页（约 6 秒）。

这是首次配置的一步，由用户做一次；之后 CLI **假定已装**，不逐次检查。没装或没跑通时 `autolock` 回退界面点击（约 20 秒，较不稳）并提示一次。`iphone init` 结束时会打印这两条命令：

| 手机与 Mac | 命令 |
|---|---|
| 同一 iCloud | `iphone setup-shortcut`：Mac 导入，经 iCloud 同步到手机，并在手机上验证 |
| 不同 iCloud | `iphone shortcut-link` 展示 iCloud 链接；用户在手机 Safari 打开并点「添加快捷指令」；再 `iphone setup-shortcut` 验证 |

- `setup-shortcut` 在 Mac 上生成并签名只含「打开 URL」（输入取「快捷指令输入」）的快捷指令，后台导入并用 `computer-use` 点掉确认框，再在**当前手机**上用 `prefs:root=BATTERY_USAGE` 实测，通过后写入 `open_url_shortcut`。Mac 上已有同名快捷指令时不重复导入，只验证。需要 macOS 的 `shortcuts` 与 `computer-use`；WDA 未运行则只导入不实测。
- `shortcut-link` 展示脚本常量 `RELAY_URL`（iCloud 分享链接，指向同一个只含一个「打开 URL」动作的快捷指令）。换了快捷指令要重新分享时，在 Mac「快捷指令」里点「共享 → 拷贝 iCloud 链接」，改这个常量。
- 手机上首次运行可能弹授权提示。命令会把弹窗文字打印出来并最多等 60 秒，需要用户本人在手机上批准。

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

## 界面点击路径的坑

- 设置 App 重开会恢复上次的滚动位置，快照里的坐标是列表还在动时的；`_poll_node` 要求坐标连续两次一致才点。
- 目标行贴着屏幕底边时，点击中心落进底部手势区，点击被吞（iPhone 14 上「显示与亮度」在 y=807/844 时必现）；`_find_scrolling` 要求节点完整落在视口 8%~90% 内才点。
- 找不到时先向下滚，到头再掉头向上。
