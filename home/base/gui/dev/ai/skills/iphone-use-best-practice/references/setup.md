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
- 设置页没有可用的 URL scheme：iOS 27.0.1 上经 WDA 打开 `prefs:` 与 `settings-navigation:` 被系统拒绝（`LSApplicationWorkspaceErrorDomain 115`）；`App-prefs:` 能打开设置，但任何带页面路径的写法都落到「App」页，只有 `App-prefs:` 本身回到设置首页。所以 `iphone autolock` 按界面逐级点击，用不随语言变的元素标识（`com.apple.settings.displayAndBrightness`、`AUTOLOCK`、选项 cell 的秒数）定位，每步滚动查找，设置后用对勾位置核验。
