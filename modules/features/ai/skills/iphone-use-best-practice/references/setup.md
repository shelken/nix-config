# 首次配置与排障

## 首次配置

`iphone up` 按本机条件自动选路，把官方 Runner 装上手机。用户不选路径，也没有参数可选（依据见 `docs/adr/0010-iphone-runner-install-routes.md`）。先做公共前提，再看自己属于哪条路径。

### 公共前提

- iPhone 用 USB 连接、解锁、信任此电脑，由用户本人完成
- go-ios（命令 `ios`）在 PATH 里，由 nix 提供，声明在 `modules/features/ai/host-commands/iphone.nix`。`iphone` 不会自己装。Xcode 路径本身不调用它
- 写配置，只有 `--bundle` 必填

```bash
iphone init --bundle <全局唯一的 bundle id，如 com.example.wda>
```

只接一台手机时自动取它的 UDID，接了多台用 `--udid` 指定。换手机或换 bundle id 要重新运行（先 `iphone down`），旧的签名产物会被删掉，`up` 会重新签名。

### 我属于哪条路径

```bash
iphone status
```

看输出里的「路径」一行。自上而下探测，前面的满足就不看后面的：

| `路径:` 的值 | 含义 | 需要什么 |
|---|---|---|
| `Xcode` | 本机 Xcode 认得这台手机 | 见「Xcode 路径」 |
| `plumesign` | Xcode 不行，plumesign 与 rcodesign 可用且 plumesign 已登录 | 见「plumesign 路径」 |
| `SideStore（未验证）` | 前两条都不行，手机上有 SideStore | 见「SideStore 路径」 |
| `没有可用路径` | 三条都不满足 | 运行 `iphone up`，报错会列出每条路径缺什么 |
| `接上 USB 才能探测` | 手机没连上 | 接线并解锁 |

`iphone up` 开头也会打印「路径」一行，另有两个值：`已就绪`（WDA 已在运行）和 `已装 Runner`（手机上已有 Runner，直接启动）。这两种不需要再装。

### Xcode 路径

适用：本机有完整 Xcode，且它认得这台手机。系统太旧的手机通常不行。

这条路径的前提沿用改造前的写法，改造后没有在真机重新验证（未验证）。

用户本人完成：

- 完整 Xcode，已同意许可：`sudo xcodebuild -license accept`、`sudo xcodebuild -runFirstLaunch`
- Xcode → Settings → Accounts 已登录 Apple ID
- iPhone 开启开发者模式

```bash
iphone init --team <TeamID> --bundle <全局唯一的 bundle id>
iphone up
```

- `--team`：Xcode 账号里个人团队的 Team ID，取法：`security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject` 的 `OU=`。只有这条路径需要它
- 首次 `up` 会拉取固定版本的 WDA 源码并用 `xcodebuild` 构建，约几分钟
- 首次 `up` 后，手机上要到「设置 → 通用 → VPN 与设备管理 → 开发者 App」信任该证书，再重新 `iphone up`
- Runner 的 bundle id 是 `<bundle id>.xctrunner`

### plumesign 路径

适用：Xcode 路径不可用，例如系统太旧、Xcode 不认这台手机。只在 iOS 15.6.1 的 iPhone 6s 上验证过，iOS 17 及以上未验证。

需要：

- plumesign（mise 固定 2.7.2）与 rcodesign（nix），都声明在 `modules/features/ai/host-commands/iphone.nix`。缺失时 `iphone` 报错并说明安装方式，不会自己装
- 一个不与其他侧载工具共用的 Apple ID

为什么要独立的 Apple ID：免费账号的开发证书有上限，实测观测到 2 个。plumesign 申请新证书超限时不询问，直接吊销现有证书，实测吊销过同账号 SideStore 的证书。不同签名工具共用一个账号会互相吊销对方的证书

登录由用户本人在终端完成，Agent 不代做：

```bash
plumesign account login -u <邮箱>
chmod -R go-rwx ~/.config/PlumeImpactor
```

- 不要加 `-p`，密码和验证码在终端里输入
- plumesign 把账号令牌明文存在 `~/.config/PlumeImpactor`，所以登录后要收紧权限
- 登录经第三方 anisette 服务器，范围与风险见 ADR 0010「后果」

然后：

```bash
iphone up
```

第一次约 2 分钟，依次做这些事：

- 下载固定版本的官方 Runner 并校验 sha256，一次性
- 手机没挂载开发者磁盘镜像时，由 go-ios 下载并挂载，首次较慢
- 第一遍 plumesign 签主 app（不带设备），rcodesign 补签 `.xctest`，第二遍 plumesign 签名并安装。补签的原因见 ADR 0010「后果」
- 用 go-ios 启动 Runner，等待 WDA 就绪
- 把自动锁定改为「永不」

另外：

- 两遍签名复用同一个证书，账号上的证书数不变（实测）
- 最后一步在不支持的设备上会多花约 130 秒，只警告不失败，可用 `iphone up --no-keep-awake` 跳过，见「已知限制」
- 之后 `up` 发现手机已装 Runner 且证书未过期，直接启动，只要几秒
- 证书 7 天过期，`up` 自动重签；剩余天数看 `iphone status` 的「证书」一行
- Runner 的 bundle id 是 `<bundle id>.runner`，与 Xcode 路径的后缀不同

### SideStore 路径（未验证）

适用：Xcode 与 plumesign 都不可用，手机上装了 SideStore。这条路径从未在设备上跑过。

`iphone up` 会下载并校验官方 Runner，打成 IPA，推到手机上 SideStore 的 Documents，然后结束，不启动 WDA。

用户需要手动做一步：在手机上打开 SideStore，添加这个 IPA 并安装。之后签名与刷新由 SideStore 管理，`iphone` 不记录过期时间。装好后运行 `iphone status` 确认 WDA 是否可用。

风险：网上有报告称 SideStore 重签会移除导入 app 的 `.xctest`，若属实装出的 Runner 起不来。出处与现状见 ADR 0010「后果」。

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

## 运行时目录

根目录是 `~/.local/share/iphone-use/`，`IPHONE_HOME` 可改。常量定义在 `scripts/iphone` 开头。

| 位置 | 内容 |
|---|---|
| `config.json` | 配置：UDID、bundle id、Team ID |
| `cli/up.log` | 启动 WDA 的日志，启动失败先看它 |
| `cli/wda.log` | go-ios `runwda` 的日志输出 |
| `cli/tools.log` | plumesign、rcodesign、go-ios 的完整输出，plumesign 路径每次安装前清空 |
| `cli/build.log` | Xcode 路径的构建日志 |
| `cli/` 其他 | `wda.pid`、`last.json`（最近一次快照）、`session`、`shots/`（截图） |
| `artifacts/wda-<版本>/` | 校验后解包的官方 Runner，不原地签名 |
| `artifacts/signed/` | plumesign 路径签好的 Runner 副本，证书过期时间读它 |
| `artifacts/images/` | go-ios 的开发者磁盘镜像 |
| `artifacts/` 下的 `.ipa` | SideStore 路径推给手机的 IPA |
| `xcode/` | 只有 Xcode 路径用：`derived_data/` 构建产物，`WebDriverAgent/` 固定版本源码 |

plumesign 的账号令牌与私钥在 `~/.config/PlumeImpactor/`，不在上面的目录里。

## 常见报错

表里写的是报错文案的开头部分，完整文案以命令输出为准。

| 现象 | 原因与处理 |
|---|---|
| `尚未配置` | 先做首次配置的 `iphone init --bundle ...` |
| `iPhone 没有通过 USB 连接`、`没有 USB 设备` | 接数据线、解锁、信任此电脑 |
| `有多台 USB 设备` | `iphone init --udid <UDID>` 指定其一 |
| `WDA 还在运行。先 iphone down` | 换设备前先 `iphone down`，再 `iphone init` |
| `没有可用的安装路径` | 三条路径都不满足。按报错里 Xcode、plumesign、SideStore 各一行补齐其一，见「首次配置」 |
| `手机系统 ... 低于下限` | 官方 Runner 装不上，先升级手机系统 |
| `缺 go-ios`、`缺 rcodesign`、`缺 plumesign` | 按报错里的安装方式装。nix 与 mise 的声明在 `modules/features/ai/host-commands/iphone.nix`，`iphone` 不会自己装 |
| `plumesign 没登录` | 用户本人登录，命令见「plumesign 路径」 |
| `同账号上其他侧载工具的证书已被吊销` | 证书数超过账号上限，plumesign 吊销了别的工具的证书。换一个不与其他侧载工具共用的 Apple ID，不要反复重试 |
| `anisette 服务器不可用` | plumesign 经第三方服务器登录。检查网络，稍后重试 |
| `plumesign 失败`、`rcodesign 失败`、`ios 失败` | 报错末尾给出 `cli/tools.log`，看完整输出。每次调用 plumesign 都可能向 Apple 申请证书，不要循环重试 |
| `没能从主程序取到签名证书`、`找不到 plumesign 的私钥` | 第一遍 plumesign 没留下证书或私钥。看 `cli/tools.log` 里它的输出，不要反复重试 |
| `下载 Runner 失败` | 检查网络后重试 |
| `Runner 的 sha256 不符，已拒绝解包` | 下载内容与固定的哈希不符。检查网络与代理后重试，不要手动放行。哈希写在脚本开头的常量里 |
| `手机锁屏，请用户本人解锁`、`手机锁屏，等待用户解锁`、`手机处于锁屏` | 用户本人解锁。启动时的前两条 `up` 会继续等，解锁后自动继续；其他命令解锁后重新运行 |
| `Runner 启动后立刻退出，多半是 .xctest 没签好` | `iphone renew` 重新签名 |
| `已装的 Runner 没起来`、`已装的 Runner 证书已过期，需要重新签名` | `up` 会继续往下探测，重新签名并安装，不用处理 |
| `WDA 还没就绪。手机若锁屏请解锁` | 启动超过 20 秒仍未就绪时的提示。解锁手机，`up` 继续等 |
| `120s 内 WDA 没就绪`（秒数随 `--timeout`） | 看 `cli/up.log` 与 `cli/wda.log` |
| `WDA 未运行` | `iphone up` |
| `WDA 在运行，但不是本 CLI 启动的` | 别的工具启动了它；先停掉那个工具 |
| `快照已过期` | 前台 App 变了；重新 `iphone snapshot` |
| `Xcode 路径需要 Team ID` | Xcode 路径：`iphone init --team <TeamID>` |
| `手机没信任开发者证书` | Xcode 路径：用户在手机上信任，再 `iphone up` |
| `Xcode 的 Apple ID 登录失效` | Xcode 路径：只能用户打开 Xcode → Settings → Accounts 重新登录一次；命令行无法登录 |
| `签名证书或描述文件缺失` | Xcode 路径：`iphone renew`；仍失败看 `cli/build.log` |
| `构建失败`、`xcodebuild 测试失败` | Xcode 路径：看 `cli/build.log`、`cli/up.log` |

## 已知限制

- 免费账号证书 7 天过期。过期后 `iphone up` 自动重签并重装（SideStore 路径除外，由 SideStore 管理）
- 免费账号最多同时装 3 个开发 App
- plumesign 路径申请新证书超过账号上限时，不询问直接吊销现有证书；实测观测到的免费账号上限是 2。要用不与其他侧载工具共用的 Apple ID
- plumesign 路径只在 iOS 15.6.1 上验证。iOS 17 及以上的设备，go-ios 需要 tunnel，没有验证，这类设备走 Xcode 路径
- Xcode 路径在改造后没有在真机重新验证，SideStore 路径从未在设备上跑过
- 自动锁定的界面点击回退在 iOS 15.6.1 上失败：报「设置里没找到 Button com.apple.settings.displayAndBrightness」，`up` 只警告不失败，但这一步耗时约 130 秒。实测的手机没装中转快捷指令，走的就是这条回退，原因未查明。`iphone up --no-keep-awake` 可以跳过
- `launch` 只认 bundle id。`xcrun devicectl device info apps` 实测只列出 5 个开发者签名的 App，不含 App Store 的 App，所以 CLI 不提供按名称启动。
- 自绘界面、部分游戏的 AX 树为空，用 `shot` 加坐标点击。
- WDA 直接打开 `prefs:` / `settings-navigation:` 会被系统拒绝（iOS 27.0.1，`LSApplicationWorkspaceErrorDomain 115`）；`App-prefs:` 带页面路径会落到「App」页。但快捷指令的「打开 URL」动作能打开 `prefs:root=DISPLAY&path=AUTOLOCK`，WDA 又能打开 `shortcuts://run-shortcut?name=…`，所以经快捷指令可一步直达任意设置页。
- 手机界面文字随系统语言变化，所以 `find`、`wait` 的关键词要用当前语言（英文系统用 `General`，不是 `通用`）。CLI 内部（`autolock`、`setup-shortcut`）只按不随语言变化的 `name` 标识（如 `com.apple.settings.displayAndBrightness`、`AUTOLOCK`、秒数）匹配，唯一例外是选中对勾的 `label == "checkmark"`（SF Symbol 名）。`setup-shortcut` 里点掉 Mac 导入确认框的 `confirm_mac_import` 按 Mac 的中文界面文字（「快捷指令」「添加快捷指令」）匹配，Mac 系统换语言会失效，此时手动点「添加快捷指令」。
- plumesign 的账号令牌明文存在 `~/.config/PlumeImpactor`，该目录要保持仅属主可访问

## 界面点击路径的坑

- 设置 App 重开会恢复上次的滚动位置，快照里的坐标是列表还在动时的；`_poll_node` 要求坐标连续两次一致才点。
- 目标行贴着屏幕底边时，点击中心落进底部手势区，点击被吞（iPhone 14 上「显示与亮度」在 y=807/844 时必现）；`_find_scrolling` 要求节点完整落在视口 8%~90% 内才点。
- 找不到时先向下滚，到头再掉头向上。
- AX 树看不出遮挡：被浮层盖住的节点照样在树里。实测英文系统的设置根页底部有悬浮搜索栏，盖住最后一行「General」，`tap-text General` 点中心会点进搜索栏，页面进入搜索态（设置 App 重开还会恢复搜索态）。先 `scroll down` 把目标滚出遮挡区再点，或用 `tap-text close` 退出搜索态；动作后看差分，出现键盘或搜索结果就是点偏了。
- `tap-text` 同样要求目标坐标连续两次一致才点，位置一直在变（页面还在滚动、动画）就报错，不会乱点。
