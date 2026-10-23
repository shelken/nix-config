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

## 自动锁定快捷指令（可选）

`iphone up` / `down` 用它把自动锁定在「永不」与 3 分钟之间切换；没配置时改走设置 App 的界面逐级点击（约 13 秒）。

1. 在「快捷指令」新建一个只含「打开 URL」的快捷指令，URL 填 `prefs:root=DISPLAY&path=AUTOLOCK`，名称自拟。
2. 把名称写进 `~/.local/share/iphone-use/config.json`：`"autolock_shortcut": "<名称>"`（`iphone init` 会重写该文件，之后需重新加上）。
3. 验证：`iphone autolock 180`，输出「自动锁定已设为 3分钟」。
