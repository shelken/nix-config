# openwrt

用 [nuci](https://github.com/lonerOrz/openwrt-nix) 声明式管理 OpenWrt 路由器的 UCI 配置。机器表 `hosts/default.nix` 里 `type = "openwrt"` 的机器（当前是 `router-mine`）把声明放在 `hosts/<机器>/`，编译成 `uci.json` 后由 nuci 对比差异、下发到路由器

可选功能，只有在 `imports` 里声明的主机才有：当前是 `mio`（`self.modules.darwin.openwrt`）。操作入口是 `just router::<配方>`，定义在 `just/router.just`

## 用法

| 命令                         | 作用                                                   |
| :--------------------------- | :----------------------------------------------------- |
| `just router::import <配置>` | 只读：把路由器上一个配置文件的现状转成 nuci 写法并打印 |
| `just router::preview`       | 对比声明与路由器现状，显示待变更的差异，不改设备       |
| `just router::push`          | 下发声明，会改路由器；回滚范围见「已知问题」           |

`preview` 与 `push` 每次按最新声明重新编译，改完声明不用单独构建；声明里的 1Password 引用在临时目录展开，需要 `op` 已登录（Touch ID）。末尾是 `0 to add, 0 to remove, 0 to change` 说明路由器与声明一致

## 迁移一个配置文件

1. 导出现状，挑出设备数据与密钥（见「数据放哪」）
   ```bash
   just router::import dhcp > hosts/router-mine/<分组>/dhcp.nix
   ```
2. 在该分组的 `default.nix` 里 `imports` 该文件；新分组再加进 `hosts/router-mine/default.nix`
3. 配置用到的包写进同一个文件的 `uci.packages`
4. `just router::preview`，差异只剩自己想改的
5. `just router::push`

nuci 只管声明里出现的配置文件，没迁移的文件原样保留。一个文件一旦声明就要写全，规则见「已知问题」

## 目录与包

`hosts/router-mine/` 按功能分组，一个 UCI 配置文件一个 `.nix`；分组目录随迁移批次建立，尚未迁移的不建空目录：

| 分组        | 内容                                        |
| :---------- | :------------------------------------------ |
| `system/`   | 设备自身：watchcat                          |
| `services/` | 不涉及接口的独立服务：rpcd、upnpd、zerotier |
| `network/`  | 靠接口名互相引用：dhcp、firewall、network   |

跨多个 UCI 文件的功能（如 zerotier）一个目录，目录里一个 UCI 文件一个 `.nix`，相关的段都写在这里。私有部分用同名目录镜像：具名段可以在私有部分补字段，匿名段是列表里独立的一条，含设备数据时整条放私有部分。

只列用户显式安装的包（opkg 标 `user installed`），依赖由 opkg 自动带上，不进列表。固件自带的包不管。列表里去掉一个包不会卸载它，卸载要写 `-包名`。没有 UCI 配置的包（如 `bird2c`）放 `services/home-ops.nix`，配置由 home-ops 下发

## 数据放哪

本仓库公开，设备运行环境数据不能进来

| 内容                                    | 位置                                                                                                                                       |
| :-------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------- |
| 结构与通用选项（区域、时区、通用开关）  | `hosts/router-mine/`                                                                                                                       |
| 设备数据（IP、MAC、主机名、VLAN、SSID） | secrets 仓库 `hosts/router-mine/`，明文 Nix，加进机器表该机器的 `uci-modules`                                                              |
| 密钥（WiFi 密码、ZeroTier secret 等）   | 1Password `Personal` 的 `router-mine` 条目；声明里写 `{{ op://Personal/router-mine/<分组>/<字段> }}`，`just router::*` 用 `op inject` 展开 |

## 已知问题

- 声明了的段里，没写的选项也会被删：设备数据与密钥写在私有部分的同一段里，私有部分没接上时 `preview` 会显示要删掉它们，此时不要 `push`
- 声明了的文件里，没写的具名段会被删：迁移时从 `import` 的输出整份开始，只删不想要的
- 没写过的匿名段类型（如 LuCI 加的静态租约 `host`）不会被删，但 `preview` 一直显示要删：要么写进声明，要么接受这条提示
- 在 LuCI 里改受管文件，下次 `push` 会被覆盖：改声明再下发
- `push` 只在 UCI 命令执行中途失败或断线时，60 秒后回滚；UCI 写完后重载服务导致断网不会回滚，60 秒后备份也被删（nuci 源码 `src/target/remote_script.rs` 的 `arm_watchdog`）：改 network、firewall 前准备好不经过这条链路的登录方式
- 含中文等非 ASCII 的值，`preview` 总显示要改：nuci 解析设备输出时按字节转字符（nuci 源码 `src/target/diff.rs` 的 `split_uci_quoted`），下发的值本身正确

## 实现

- `default.nix`：用 mise 安装 nuci，版本读自 flake 输入 `openwrt-nix` 的 `Cargo.toml`，编译声明的 Nix 模块与执行它的二进制同版本；为每台 `type = "openwrt"` 的机器产出 `<机器>-uci` 包
- `uci2nix`：经 `ubus call uci get` 取 JSON，jq 转成 nuci 结构，由 `nix eval` 打印成 Nix
- 升级 nuci：改 `flake.nix` 里 `openwrt-nix` 的 tag，再 `nix flake lock --update-input openwrt-nix`
- `hosts/router-mine/` 不是 Nix 系统，`lib/default.nix` 的 `calcUniformSchedule` 把它排除在备份排程之外
