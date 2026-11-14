# openwrt

用 [nuci](https://github.com/lonerOrz/openwrt-nix) 声明式管理 OpenWrt 路由器的 UCI 配置、少数非 UCI 文件与软件包。机器表 `hosts/default.nix` 里 `type = "openwrt"` 的机器（当前是 `router-mine`）把声明放在 `hosts/<机器>/`，编译成 `uci.json` 后由 nuci 对比差异、下发到路由器。设计原因见文末「设计决策」

可选功能，只有在 `imports` 里声明的主机才有：当前是 `mio`（`self.modules.darwin.openwrt`）。操作入口是 `just router::<配方>`，定义在 `just/router.just`

## 用法

| 命令                         | 作用                                                   |
| :--------------------------- | :----------------------------------------------------- |
| `just router::import <配置>` | 只读：把路由器上一个配置文件的现状转成 nuci 写法并打印 |
| `just router::preview`       | 对比声明与路由器现状，显示待变更的差异，不改设备       |
| `just router::push`          | 下发声明，会改路由器；回滚范围见「已知问题」           |

- `preview` 与 `push` 每次按最新声明重新编译，改完声明不用单独构建
- 声明里的 1Password 引用在临时目录展开，需要 `op` 已授权（Touch ID），未授权时超时失败
- 输出经打码：规则由 `mask.jq` 从声明里的引用位置生成，另对 MAC 与由 MAC 推出的 IPv6 后缀兜底。`uci.files` 的 `content` 里的引用不在打码范围
- 末尾是 `0 to add, 0 to remove, 0 to change` 说明路由器与声明一致。匿名段按位置对比，列表里新增或移动条目会让 `preview` 出现一次序号噪声，下发后消失；要核对内容是否一致，按段内容对比，不看序号
- `push` 在下发后补做 nuci 不做的事：`bird -p` 通过才 `birdc configure`，Avahi 配置变化才重启。热点中继（`wifinet7`）在 LuCI 里开启时拒绝下发，否则声明里它是关闭的，下发会把它关掉并让路由器断网

## 迁移一个配置文件

1. 导出现状，挑出设备数据与密钥（见「数据放哪」）
   ```bash
   just router::import dhcp
   ```
2. 写进 `hosts/router-mine/<分组>/` 下对应的 `.nix`，在该分组的 `default.nix` 里 `imports`
3. 配置用到的包写进同一个文件的 `uci.packages`
4. `just router::preview`，差异只剩自己想改的
5. `just router::push`

nuci 只管声明里出现的配置文件，没声明的文件原样保留。一个文件一旦声明就要写全，规则见「已知问题」

## 目录与包

`hosts/router-mine/` 按功能分组，同一个功能的配置放在同一个文件或目录，即使它横跨多个 UCI 文件。各目录的职责与引入原则见 `hosts/router-mine/README.md`

| 位置           | 内容                                                                      |
| :------------- | :------------------------------------------------------------------------ |
| `system/`      | 设备自身：watchcat、dropbear（SSH 登录与授权密钥）                        |
| `network/`     | 靠接口名互相引用的通用部分：dhcp、firewall、network、wireless             |
| `services/`    | 独立服务：zerotier                                                        |
| `home-ops/`    | 与 home-ops 有关的一切：BIRD、Avahi、DNS、IoT 网、对外放行规则            |
| `hk1box/`      | 与旁路由 hk1box 配合：DHCP 选项、IoT 出网的策略路由与防火墙规则           |
| `hardware.nix` | 机型相关的值：射频的硬件路径、口名。纯数据，由 `network/` 下文件 `import` |

只列用户显式安装的包（opkg 标 `user installed`），依赖由 opkg 自动带上，不进列表。固件自带的包不管。列表里去掉一个包不会卸载它，卸载要写 `-包名`。没有 UCI 配置的包（如 `bird2c`）与它的配置文件写在同一个 `.nix`

## 数据放哪

本仓库公开，设备运行环境数据不能进来

| 内容                                                   | 位置                                                                                             |
| :----------------------------------------------------- | :----------------------------------------------------------------------------------------------- |
| 结构与通用选项                                         | `hosts/router-mine/`                                                                             |
| 网段与已登记主机的 IP                                  | `vars/networking.nix`，声明里用 `net.hostAddress.<名>.address` 引用                              |
| MAC、IPv6 后缀、SSID、WiFi 密码、ZeroTier 密钥与设备名 | 1Password `Personal` 的 `router-mine` 条目，按功能分组（`zerotier`、`dhcp`、`firewall`、`wifi`） |

声明里写 `{{ op://Personal/router-mine/<分组>/<字段> }}`，`just router::*` 用 `op inject` 展开到临时目录，退出即删；仓库与 Nix store 里只有引用。往条目里新增字段时，用脚本从路由器直接读值写入，不要经过会话输出

## 非 UCI 文件

`uci.files` 把文件写成给定内容，只写不删，写入后不校验也不重载服务。每个这样的文件都要在 `just/router.just` 的 `push` 里补上校验与生效，当前有 BIRD 与 Avahi。核对文件内容用 `jq -j` 取内容再算校验和，`-r` 会多补一个换行

## 声明之外的东西

下面这些不在声明里，设备重建时不会跟着回来：

- home-ops 的 homepage 路由器小组件依赖 rpcd ACL 文件 `/usr/share/rpcd/acl.d/homepage.json`，靠 `/etc/sysupgrade.conf` 保留，home-ops 改读 Prometheus（home-ops 的 `#1800`）之前一直需要
- `system`（时区、NTP、日志）、`sysctl` 的本地设置（`/etc/sysctl.d/50-local.conf`）
- LuCI、nginx、已停用的 passwall 与 shadowsocks-libev、upnpd 及主题类配置

## 已知问题

- 声明了的段里，没写的选项也会被删：设备数据与密钥要写进同一段里，漏写时 `preview` 会显示要删掉它们，此时不要 `push`
- 声明了的文件里，没写的具名段会被删：迁移时从 `import` 的输出整份开始，只删不想要的
- 没声明过的匿名段类型（如 LuCI 加的静态租约 `host`）不会被删，但 `preview` 一直显示要删：要么写进声明，要么接受这条提示。已声明类型里多出的匿名项，下发时会被删
- 在 LuCI 里改受管文件，下次 `push` 会被覆盖：改声明再下发
- `push` 只在 UCI 命令执行中途失败或断线时，60 秒后回滚；UCI 写完后重载服务导致断网不会回滚，60 秒后备份也被删（nuci 源码 `src/target/remote_script.rs` 的 `arm_watchdog`）：改 network、firewall、wireless 前准备好不经过这条链路的登录方式
- `sshKeys` 整份覆盖 `authorized_keys`；部署者（本机 ssh-agent）的公钥不在列表里时 nuci 会追加它，防止锁死
- 含中文等非 ASCII 的值，`preview` 总显示要改：nuci 解析设备输出时按字节转字符（nuci 源码 `src/target/diff.rs` 的 `split_uci_quoted`），下发的值本身正确。`name` 只用 ASCII 可以避开
- `nuci diff` 会原样打印路由器上现有的值，包括被删除行里的秘密：不要绕过 `just router::preview` 直接跑

## 实现

- `default.nix`：用 mise 安装 nuci，版本读自 flake 输入 `openwrt-nix` 的 `Cargo.toml`，编译声明的 Nix 模块与执行它的二进制同版本；为每台 `type = "openwrt"` 的机器产出 `<机器>-uci` 包
- `uci2nix`：经 `ubus call uci get` 取 JSON，jq 转成 nuci 结构，由 `nix eval` 打印成 Nix
- `mask.jq`：从未展开的声明里找出写了 `{{ op://… }}` 的位置，生成输出打码规则
- 升级 nuci：改 `flake.nix` 里 `openwrt-nix` 的 tag，再 `nix flake lock --update-input openwrt-nix`
- `hosts/router-mine/` 不是 Nix 系统，`lib/default.nix` 的 `calcUniformSchedule` 把它排除在备份排程之外

## 设计决策

每节记录为什么这样设计和考虑过的替代方案。机制本身与代价见上文各节

### 用 nuci 声明，配置只在本仓库下发

路由器的 UCI 配置、少数非 UCI 文件与软件包都在 `hosts/router-mine/` 声明，由 nuci 对比差异后下发。DNS、BIRD、Avahi 原先在 home-ops 下发，已迁到这里（home-ops 的 ADR-0009、ADR-0010）

- **dewclaw**：整文件替换，没有差异预览，会删掉不在保留列表里的 `/etc/config` 文件，LuCI 里拨的开关和未声明的段都会丢
- **Ansible `community.openwrt`**：能满足需求，但要维护 playbook 与「删除」的墓碑项，不是声明式
- **LuCI 手工加脚本**：无法审查，也无法在换设备时复现
- **配置分在 home-ops 与本仓库两处下发**：同一台路由器有两个所有者，换设备要两处重建

### 秘密与设备标识走 1Password 引用

声明里只写 `op://` 引用，下发时在临时目录展开，见「数据放哪」

- **nuci 自带的 sops 支持**：每台操作机都要带 age 密钥；本仓库的其他外部秘密（如 singbox 配置）已经用 `op://` 引用，沿用同一套
