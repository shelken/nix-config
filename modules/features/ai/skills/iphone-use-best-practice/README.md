# iphone 的设计

[scripts/iphone](./scripts/iphone) 通过 WebDriverAgent（WDA）读取并操作 USB 连接的真实 iPhone。用法见 [SKILL.md](./SKILL.md)，首次配置与排障见 [references/setup.md](./references/setup.md)，go-ios、rcodesign、plumesign 的 nix 与 mise 声明在 [host-commands/iphone.nix](../../host-commands/iphone.nix)。本文记录术语、不变量和设计决策

## 术语与不变量

- **Runner**: 安装在手机上的 WebDriverAgent 测试运行器，`iphone` 通过它读取并操作手机界面。_避免_: WDA 包、agent app
- **签名路径 (Signing Route)**: 把 Runner 装上手机的方式，分为 Xcode 路径、plumesign 路径、SideStore 路径，由 `iphone up` 按本机条件自动选择，用户不选。_避免_: 签名方式、安装模式
- **启动方式 (Launch Channel)**: 把已装的 Runner 跑起来并等 WDA 就绪的方式，分 `xcodebuild test-without-building`（iOS 17 及以上）与 go-ios `runwda`（旧系统），由手机系统决定，用户不选
- **Xcode 可服务设备**: 本机完整 Xcode 的 `devicectl` 认得、且本机已配置 Team 的手机，系统过旧的手机不属于。_避免_: Xcode 支持的设备

不变量：

1. 签名路径只由探测决定，不接受用户指定
2. `iphone` 只下载固定版本并校验过的 Runner 产物，不下载其他二进制
3. 不同签名工具共用一个 Apple ID，且申请新证书超过账号上限时，已有的证书会被吊销，另一个工具的签名随之失效
4. 免费描述文件在一台设备上同时最多装 3 个 App，跨团队计数，装新的 Runner 前要先腾出名额

## 按本机条件自动选路安装 Runner，旧设备不依赖 Xcode

日期: 2026-10-25

`iphone up` 原来只走 `xcodebuild`。iOS 15 的设备上 Xcode 27.1 不认设备，产物又被 SDK 抬到 iOS 17，而 Xcode 本身是最重的前置条件。现在 `up` 自动探测：已装的 Runner 直接启动，Xcode 能服务该设备就走 Xcode，否则走 plumesign 加 rcodesign，最后才是 SideStore，用户不选路径。~~Xcode 能否服务设备看 `xcrun devicectl` 是否认得该设备~~，`devicectl` 认得之外还要已配置 Team，选路与启动方式见下面 2026-11-02 一节。探测顺序见 [scripts/iphone](./scripts/iphone)

### 后果

- 只下载官方 WDA v16.15.3 的 Runner zip，固定版本并校验 sha256。go-ios、rcodesign 由 nix 提供，plumesign 由 mise 固定 2.7.2，`iphone` 不下载也不安装它们
- plumesign 不签 `PlugIns` 下的 `.xctest`，不补签会被设备拒绝加载，Runner 随即退出。所以先签主 app 取得证书，用 rcodesign 补签 `.xctest`，再封一遍整包，安装见下面 2026-11-02 一节；plumesign 的 `--udid` 实际比较 usbmuxd 的数字 DeviceID
- 免费账号开发证书上限为 2，plumesign 超限时不询问直接吊销现有证书，实测吊销过同账号 SideStore 的证书；plumesign 路径要用不与其他侧载工具共用的 Apple ID
- plumesign 经第三方 anisette 服务器登录，令牌明文存在 `~/.config/PlumeImpactor`。登录用 SRP，已读的源码范围内 anisette 模块不碰 Apple ID 密码，但它对服务器与 Apple `lookup` 请求关闭了证书校验（源码标注 TODO），整条链路没有完整审计
- ~~iOS 17 及以上只走 Xcode 路径：go-ios 在这类系统上需要 tunnel，没有验证~~，这类系统的安装与启动已实测可用，见下面 2026-11-02 一节
- plumesign 路径与 Xcode 路径的 Runner 用不同的 bundle id 后缀（`.runner`、`.xctrunner`），避免两个团队注册同名 App ID，是否真会冲突没有验证
- SideStore 路径未验证：网上有报告称 SideStore 重签会移除导入 app 的 `PlugIns/*.xctest`（LiveContainer/LiveContainer#1489，altstoreio/AltStore#1692 是同类现象），若属实装出的 Runner 起不来

### 考虑过的替代方案

- **所有设备统一用官方 Runner 加重签，删除 Xcode 路径**：Xcode 路径能覆盖同一批设备，两套并存没有代价
- **旧设备也本机编译**：SDK 抬高部署目标，产物装不进
- **go-ios 自带的 `ui install`**：需要 P12 与 profile，go-ios 只提供经 App Store Connect API 密钥生成的方式，免费账号没有来源
- **SideStore 作为唯一路径**：每次都要用户手动点击，且存在 `.xctest` 被移除的风险
- **用 go-ios 的 tunnel 启动 WDA**：iOS 17 及以上要额外建 tunnel，`iphone up` 与 `iphone` 读界面都要为它让路；`xcodebuild test-without-building` 已能启动这类设备，见下面一节

## 签名与启动分开，iOS 17 及以上不用 Xcode 账号也能起 WDA

日期: 2026-11-02

`iphone up` 原来把「把 Runner 装上手机」和「把 Runner 跑起来」当成一件事，启动交给 go-ios，于是 iOS 17 及以上（go-ios 的 XCTest 会话需要 tunnel）只能落到需要 Xcode 账号的路径。实测（iPhone 14，iOS 27.2，Xcode 未登录 Apple ID）这两件事可以分开：

- `xcodebuild test-without-building -xctestrun <文件> -destination id=<UDID>` 能启动手机上已装的 Runner，不需要 Xcode 账号，不需要 `-allowProvisioningUpdates`，也不需要 tunnel
- 它只按 xctestrun 启动，日志里没有任何安装、签名或描述文件的行，所以安装必须另做一步
- plumesign 路径的安装用 `xcrun devicectl device install app`，不用 plumesign 的 `--register-and-install`
- `iphone` 读界面走 usbmuxd 直连手机的 8100 端口，与这个启动方式无关

现在选路分两层，用户都不选：

| 层 | 取值 | 由什么决定 |
|---|---|---|
| 装法 | Xcode / plumesign / SideStore（未验证） | 本机条件：`devicectl` 认得设备且已配置 Team，plumesign 与 rcodesign 可用并已登录，手机上有 SideStore |
| 启法 | `xcodebuild test-without-building` / go-ios `runwda` | 手机系统：iOS 17 及以上用前者，旧系统保持 `runwda` |

### 后果

- `iphone` 自己生成 xctestrun（v1 格式），与签好的 app 一起放在 `artifacts/signed/` 的启动布局里：xctestrun 在目录根，app 在它旁边的 `Debug-iphoneos/`。这套东西跟随签名产物一起被清理与重建
- 启法看手机系统版本，iOS 17 是分界，读不到版本时按旧系统处理。旧系统的设备通常也不被 `devicectl` 认得，装法因此退回 plumesign 经 AFC 安装。旧设备的路径没有变
- 已装的 Runner 这一档不再跳过：iOS 17 及以上先试启动它，起不来或本机没有对应产物才往下走去重装
- 装之前先查免费描述文件的 3 个 App 名额，满了就报出该卸哪个（旧的 Runner 优先），不签完一遍才发现装不上。安装失败时把 iOS 的原始报错连同名单一起回显
- 第二遍签名不再带 `--register-and-install`：那个开关把注册设备、签名、安装绑在一起，撞上名额上限时失败发生在签名之后，前面那遍签名白做
- 免费描述文件的名额按「团队 + bundle id」在设备上计数，同一份 Runner 覆盖安装不占新名额
- Xcode 路径未走这条启动方式：它的 `xcodebuild` 直接按工程与构建产物启动，不需要 xctestrun
- 手机锁屏时 `xcodebuild` 报 `Code=-3 "Unlock … to Continue"` 并一直等，`iphone` 认这条报错并提示用户解锁，解锁后它自己继续

### 考虑过的替代方案

- **沿用 plumesign 的 `--register-and-install`，只换启动方式**：安装失败发生在签名之后，碰上名额上限会白签一遍，且它的安装走 usbmuxd 的 AFC，`devicectl` 已经在用 CoreDevice
- **自己用 go-ios 的 userspace tunnel 启动**：要额外维护一条隧道与它的生命周期，而 `xcodebuild` 启动不需要本项目管理任何通道
- **让 plumesign 路径与 Xcode 路径共用一个 bundle id**：两条路径签名用的团队不同，同一个 App ID 能否被两个团队各自注册没有验证
