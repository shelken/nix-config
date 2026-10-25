# 0010 iphone 的 Runner 按本机条件自动选路安装，旧设备不依赖 Xcode

日期: 2026-10-25
状态: Accepted

## 背景

`iphone up` 原先只有 `xcodebuild` 一条路。在 iOS 15.6.1 的 iPhone 6s 上实测有两处失败：

1. Xcode 27.1 的 SDK 把产物的部署目标抬到 17.0，装不进设备
2. Xcode 不认这台设备，自动生成的 profile 不含它

Xcode 本身也是用户最重的前置条件：数 GB 磁盘，并要求在 Xcode 里登录 Apple ID

官方 WDA release（appium/WebDriverAgent v16.15.3）的 Runner 最低 iOS 13.0，包内 `WebDriverAgentRunner.xctest` 最低 iOS 15.0，没有开发者签名，装到设备前必须重签

## 决策

1. **WDA 产物只用官方 release**：固定 v16.15.3 的 `WebDriverAgentRunner-Runner.zip`，下载后校验 sha256。版本与哈希写成 `scripts/iphone` 开头的常量，禁止 latest 与运行时解析版本。这个 zip 是 `iphone` 唯一下载的二进制，代码保持单文件
2. **设备系统下限取 Runner 与 xctest 两个组件 `MinimumOSVersion` 的最大值**，当前为 15.0
3. **用户不选路径**：`iphone up` 按下表自上而下探测，不提供选择签名方式的参数

   | 顺序 | 条件                                                 | 动作                                                                   |
   | ---- | ---------------------------------------------------- | ---------------------------------------------------------------------- |
   | 1    | WDA 已就绪                                           | 结束                                                                   |
   | 2    | 手机上已装 Runner 且 `runwda` 能起                   | 直接启动                                                               |
   | 3    | 设备系统低于下限                                     | 报错                                                                   |
   | 4    | Xcode 可服务该设备                                   | Xcode 路径：`xcodebuild` 编译、签名、安装并启动                        |
   | 5    | `plumesign` 与 `rcodesign` 可用，且 plumesign 已登录 | plumesign 路径                                                         |
   | 6    | 手机上有 SideStore                                   | SideStore 路径：把 IPA 推到手机，用户在 SideStore 里手动安装并自行管理 |
   | 7    | 以上都不满足                                         | 报错并列出可行方案                                                     |

4. **「Xcode 可服务该设备」的判据**：`xcrun devicectl list devices --json-output` 的结果里，有物理设备的 `hardwareProperties.udid` 等于配置的 UDID。不比较版本号。没有完整 Xcode 时命令失败，按「否」处理
5. **plumesign 路径的步骤**：
   - 第一遍：`plumesign sign --apple-id` 不带设备，只签主 app，用来取得证书。没有这一步就没有证书可供 `rcodesign` 使用，证书上限也决定了不能靠多装一份来取得
   - 从已签的主程序提取证书，用 `rcodesign` 补签 `.xctest`（连同其内的 framework）
   - 第二遍：`plumesign sign --apple-id --register-and-install` 签名主 app 并安装
   - 最后用 go-ios 的 `runwda` 启动

   补签是必需的：plumesign 只处理 `.framework` 与 `.appex`，不签 `PlugIns` 下的 `.xctest`，设备报 `code signature ... not valid` 并拒绝加载测试包，Runner 随即退出。另外 plumesign 的 `--udid` 实际比较的是 usbmuxd 的数字 DeviceID，不是 UDID

6. **依赖来源**：go-ios（取 nixpkgs 版本，实测 1.3.2）与 `rcodesign` 由 nix 提供，`plumesign` 由 mise 固定 2.7.2，Xcode 用系统已装的。`iphone` 不下载也不安装这些工具，缺失时报错并说明安装方式
7. **SideStore 路径保留，标注未验证**：见下文已知限制。路径结束时提示用户用 `iphone status` 确认 WDA 是否可用
8. **Xcode 路径编译的 WDA 源码与官方 Runner 同版本**：对齐到 v16.15.3 对应的 commit，写成 `scripts/iphone` 开头的常量。两条路径跑同一版本的 WDA，行为一致
9. **Runner 的 bundle id 按路径区分**：Xcode 路径沿用 `<bundle_id>.xctrunner`，plumesign 路径用 `<bundle_id>.runner`，避免两条路径在不同团队下注册同名显式 App ID（不同团队之间是否冲突没有验证，换后缀是回避）。`iphone init --bundle` 是唯一必填项，`--team` 只在走 Xcode 路径时才需要。路径表第 2 行识别已装 Runner 时按三档匹配：`<bundle_id>.runner`、`<bundle_id>.xctrunner`、以官方原始 id 为前缀的 id，匹配到哪个就用哪个启动。第三档对应 SideStore 重签后的 id，是否加后缀没有验证
10. **过期判断复用签名后的副本**：plumesign 路径保留签名后的 Runner，过期时间读其 `embedded.mobileprovision`，与 Xcode 路径同一套逻辑，不新增状态。SideStore 路径不记录过期，由 SideStore 管理；`renew` 的含义是对当前路径强制重新签名并安装。进入 plumesign 路径就一定签名并安装：已装 Runner 启动失败后，不能因为本地副本未过期而跳过安装，证书被吊销时本地到期时间仍然大于零
11. **iOS 17 及以上只走 Xcode 路径**：go-ios 在这类系统上需要 tunnel，没有验证。设备系统不低于常量 `GOIOS_TUNNEL_MIN_OS` 时，路径表第 2、5、6 行不可用，Xcode 判据失败后在调用 plumesign 之前直接报错，避免白白消耗证书上限

## 实测依据

2026-10-25，iPhone 6s（iOS 15.6.1），macOS 27，Xcode 27.1：

- 官方 Runner、补签 `.xctest`、plumesign 签名安装、nix 的 go-ios 1.3.2 `runwda`：WDA 就绪，`iphone snapshot` 读到界面
- 只用 plumesign 签名：Runner 启动后退出，go-ios 报 `broken pipe`。go-ios 1.3.2 与比它新 44 个提交的源码构建表现一致，所以原因不在 go-ios 版本
- 本机 Xcode 27.1 编译 appium 16.14.0 源码：产物 `MinimumOSVersion` 为 17.0
- 判据 4 的对照：`devicectl` 列出 iPhone 14、iPhone 17 的 UDID 行，iPhone 6s 只有一行仅含 ECID 的记录

复现判据 4：

```bash
xcrun devicectl list devices --json-output devices.json
```

## 已知限制与风险

- **plumesign 申请新证书超过账号上限时，不询问直接吊销现有证书**。实测吊销了同账号 SideStore 的证书，观测到的免费账号上限为 2。plumesign 路径要用不与其他侧载工具共享的 Apple ID
- **plumesign 经第三方 anisette 服务器登录**，默认 `mac-ani.jkcoxson.com`，接受这个依赖。源码审阅范围：登录用 SRP；anisette 模块里没有 Apple ID 密码，只有一次性的 anisette 值；anisette 客户端对服务器与 Apple `lookup` 请求关闭了证书校验（源码标注 TODO）。整条登录链路没有完整审计
- plumesign 把账号令牌明文存在 `~/.config/PlumeImpactor`，该目录需保持仅属主可访问
- plumesign 路径只在 iOS 15.6.1 上验证。iOS 17 及以上的设备，go-ios 需要 tunnel，没有验证，这类设备走 Xcode 路径
- **SideStore 路径未验证**：网上有报告称 SideStore 重签会移除导入 app 的 `PlugIns/*.xctest`（LiveContainer/LiveContainer#1489，altstoreio/AltStore#1692 是同类现象）。若属实，装出的 Runner 起不来。当前手机上的 SideStore 是 nightly 版本，没有在设备上验证过

## 考虑过的替代方案

- **所有设备统一用官方 Runner 加重签，删除 Xcode 路径**：iOS 17 及以上设备要 go-ios tunnel，未验证
- **旧设备也本机编译**：SDK 抬高部署目标，产物装不进
- **go-ios 自带的 `ui install` / `sign app`**：需要 P12 与 profile，go-ios 只提供经 App Store Connect API 密钥生成的方式，该接口需要付费开发者账号，免费账号没有来源
- **SideStore 作为唯一路径**：每次都要用户手动点，且有上面的 `.xctest` 风险
- **xtool**：构建与签名都要 Xcode 的 iOS SDK
- **Sideloader**：最后一次发布在 2024 年
- **用 nvfetcher 管理 plumesign**：与维护者习惯不符，工具只用 nix 或 mise 管
- **`iphone` 自己下载 plumesign 或 go-ios**：违反「只下载 WDA」
