# iphone 的设计

[scripts/iphone](./scripts/iphone) 通过 WebDriverAgent（WDA）读取并操作 USB 连接的真实 iPhone。用法见 [SKILL.md](./SKILL.md)，首次配置与排障见 [references/setup.md](./references/setup.md)，go-ios、rcodesign、plumesign 的 nix 与 mise 声明在 [host-commands/iphone.nix](../../host-commands/iphone.nix)。本文只记录设计决策

## 按本机条件自动选路安装 Runner，旧设备不依赖 Xcode

日期: 2026-10-25

`iphone up` 原来只走 `xcodebuild`。iOS 15 的设备上 Xcode 27.1 不认设备，产物又被 SDK 抬到 iOS 17，而 Xcode 本身是最重的前置条件。现在 `up` 自动探测：已装的 Runner 直接启动，Xcode 能服务该设备就走 Xcode，否则走 plumesign 加 rcodesign，最后才是 SideStore，用户不选路径。Xcode 能否服务设备看 `xcrun devicectl` 是否认得该设备，不比较版本号，探测顺序见 [scripts/iphone](./scripts/iphone)。

### 后果

- 只下载官方 WDA v16.15.3 的 Runner zip，固定版本并校验 sha256。go-ios、rcodesign 由 nix 提供，plumesign 由 mise 固定 2.7.2，`iphone` 不下载也不安装它们
- plumesign 不签 `PlugIns` 下的 `.xctest`，不补签会被设备拒绝加载，Runner 随即退出。所以先签主 app 取得证书，用 rcodesign 补签 `.xctest`，再签名安装。plumesign 的 `--udid` 实际比较 usbmuxd 的数字 DeviceID
- 免费账号开发证书上限为 2，plumesign 超限时不询问直接吊销现有证书，实测吊销过同账号 SideStore 的证书。plumesign 路径要用不与其他侧载工具共用的 Apple ID
- plumesign 经第三方 anisette 服务器登录，令牌明文存在 `~/.config/PlumeImpactor`。登录用 SRP，已读的源码范围内 anisette 模块不碰 Apple ID 密码，但它对服务器与 Apple `lookup` 请求关闭了证书校验（源码标注 TODO），整条链路没有完整审计
- iOS 17 及以上只走 Xcode 路径：go-ios 在这类系统上需要 tunnel，没有验证
- plumesign 路径与 Xcode 路径的 Runner 用不同的 bundle id 后缀（`.runner`、`.xctrunner`），避免两个团队注册同名 App ID，是否真会冲突没有验证
- SideStore 路径未验证：网上有报告称 SideStore 重签会移除导入 app 的 `PlugIns/*.xctest`（LiveContainer/LiveContainer#1489，altstoreio/AltStore#1692 是同类现象），若属实装出的 Runner 起不来

### 考虑过的替代方案

- **所有设备统一用官方 Runner 加重签，删除 Xcode 路径**：iOS 17 及以上的 go-ios tunnel 没有验证
- **旧设备也本机编译**：SDK 抬高部署目标，产物装不进
- **go-ios 自带的 `ui install`**：需要 P12 与 profile，go-ios 只提供经 App Store Connect API 密钥生成的方式，免费账号没有来源
- **SideStore 作为唯一路径**：每次都要用户手动点，且有上面的 `.xctest` 风险
