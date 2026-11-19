# openwrt

用 [nuci](https://github.com/lonerOrz/openwrt-nix) 声明式管理 OpenWrt 路由器的 UCI 配置、少数非 UCI 文件与软件包。机器表 `hosts/default.nix` 里 `type = "openwrt"` 的机器（当前是 `router-mine`）把声明放在 `hosts/<机器>/`，编译成 `uci.json` 后由 nuci 对比差异、下发到路由器。固件本身也由声明生成，经 ASU 云端构建，见「固件」。设计原因见文末「设计决策」

可选功能，只有在 `imports` 里声明的主机才有：当前是 `mio`（`self.modules.darwin.openwrt`）。操作入口是 `just router::<配方>`，定义在 `just/router.just`

## 用法

| 命令                           | 作用                                                   |
| :----------------------------- | :----------------------------------------------------- |
| `just router::import <配置>`   | 只读：把路由器上一个配置文件的现状转成 nuci 写法并打印 |
| `just router::preview`         | 对比声明与路由器现状，显示待变更的差异，不改设备       |
| `just router::push`            | 下发声明，会改路由器；回滚范围见「已知问题」           |
| `just router::firmware-update` | 按软件源当前版本构建固件并重写锁文件，不改设备         |
| `just router::firmware-build`  | 按锁文件构建并下载固件，版本不一致时失败，不改设备     |
| `just router::acceptance`      | 采集路由器状态与内网吞吐，只读，结果存本机             |
| `just router::acceptance-diff` | 并排对比两份验收结果                                   |

- `preview` 与 `push` 每次按最新声明重新编译，改完声明不用单独构建
- 声明里的 `{{ sops.… }}` 占位符由 `sops -d` 解密后在临时目录展开，需要 `SOPS_AGE_KEY_FILE` 指向 admin_mio 的 age 密钥；解不开，或占位符在 sops 里没有值时报错退出，不会把占位符下发
- 输出经打码：规则由 `mask.jq` 从声明里的占位符位置生成，另对 MAC 与由 MAC 推出的 IPv6 后缀兜底。`uci.files` 的 `content` 里的占位符不在打码范围
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

## 固件

固件是版本控制的单位：发行版、内核与全部包一起换。路由器上不跑 `apk upgrade`，原地升级会装上与内核不匹配的 kmod，只读层与 overlay 的库也会错版

- `hosts/<机器>/firmware.nix`：服务器、发行版本、target、profile 与不属于任何功能的包（主题、中文），由 `hosts/default.nix` 的 `firmware` 字段引用
- 请求里的包 = `firmware.nix` 的 `packages` 加各功能的 `uci.packages`，去重排序。功能用到的包只写在功能文件里，固件与 nuci 共用一份
- `hosts/<机器>/firmware.lock.json`：上次构建的请求、`version_code`、镜像名与 sha256、全部包的版本。由 `firmware-update` 生成，提交前审查 diff
- 镜像只放本机 `${XDG_DATA_HOME:-~/.local/share}/router-firmware/<机器>/`，保留最新 3 个，锁文件指向的不删。软件源更新后旧版本就构建不出来了，回滚靠这些文件

升级或改了包：

1. 改 `firmware.nix` 的 `version`，或改功能文件的 `uci.packages`
2. `just router::firmware-update`，用 `git diff` 审查锁文件里的版本变化
3. 刷机前 `just router::acceptance` 采一份基线
4. 上传镜像到路由器 `/tmp`，`sysupgrade` 保留配置刷入；发行版或包管理器变了时用 `sysupgrade -n`，刷完 `just router::push` 恢复配置
5. 再跑 `just router::acceptance`，`just router::acceptance-diff <前> <后>` 对比

验收采集路由器状态（网口协商速率与断线次数、PPE 硬件卸载条目、mt7915 固件版本、射频参数）与本机 WiFi 到 sakamoto 有线口的 iperf3 双向吞吐。WiFi 吞吐先看 `client_*` 的信道、信号与协商速率是否相近，再比较数字。结果含设备运行数据，只放本机镜像目录下的 `acceptance/`

`firmware-build` 只在声明与锁文件的请求一致时构建，构建出的包版本与锁文件逐个对照，用于镜像丢了时按锁文件重建。ASU 构建失败的结果按请求 hash 缓存，服务端故障（如 Redis 连不上）导致的失败要等缓存过期再试；网关 502 由脚本自动重试。镜像会按 hash 缓存在公共服务器上，请求里不放机密，机密仍由 `push` 下发

## 目录与包

`hosts/router-mine/` 按功能分组，同一个功能的配置放在同一个文件或目录，即使它横跨多个 UCI 文件。各目录的职责与引入原则见 `hosts/router-mine/README.md`

| 位置           | 内容                                                                        |
| :------------- | :-------------------------------------------------------------------------- |
| `system/`      | 设备自身：watchcat、dropbear（SSH 登录与授权密钥）                          |
| `network/`     | 靠接口名互相引用的通用部分：dhcp、firewall、network、wireless               |
| `services/`    | 独立服务：zerotier                                                          |
| `home-ops/`    | 与 home-ops 有关的一切：BIRD、Avahi、DNS、IoT 网、对外放行规则              |
| `hk1box/`      | 与旁路由 hk1box 配合：DHCP 选项、IoT 出网的策略路由与防火墙规则             |
| `hardware.nix` | 机型相关的值：射频的硬件路径、口名。纯数据，由 `network/` 下文件 `import`   |
| `firmware.nix` | 固件的发行版、机型与界面包。纯数据，由 `hosts/default.nix` 引用，见「固件」 |

只列功能显式需要的包，依赖由 apk 自动带上，不进列表。发行版默认包不管。LuCI 的包先查有没有 `luci-i18n-<名>-zh-cn`，有就只写它：翻译包依赖本体（`luci.mk` 的 `LuciTranslation`），本体不重复声明。列表里去掉一个包不会卸载它，卸载要写 `-包名`。没有 UCI 配置的包（如 `bird2c`）与它的配置文件写在同一个 `.nix`

## 数据放哪

本仓库公开，设备运行环境数据不能进来

| 内容                                                     | 位置                                                                                                                                                                     |
| :------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 结构与通用选项                                           | `hosts/router-mine/`                                                                                                                                                     |
| 网段与已登记主机的 IP                                    | `vars/networking.nix`，声明里用 `net.hostAddress.<名>.address` 引用                                                                                                      |
| 实体设备的 MAC（DHCP 静态租约）                          | secrets.nix 的明文 nix：k8s 节点读 `hosts/<节点>/network.nix` 的 `lanMac`，其余读 `hosts/router-mine/network.nix` 的 `dhcpMacs`，声明里 `import (inputs.secrets + "/…")` |
| SSID、WiFi 密码、ZeroTier 的 secret、network-id 与设备名 | secrets.nix 的 sops 密文 `sops/secrets/hosts/router-mine.yaml`（`wifi`、`zerotier`），声明里写 `{{ sops.<路径> }}` 占位符                                                |
| 对外放行规则的 IPv6 后缀                                 | `hosts/router-mine/home-ops/firewall.nix`：后缀由 home-ops 里服务的 Multus 固定 MAC 推出，是手动随机生成的服务配置，不算私密，明文写在声明里                             |

划分规则见 `docs/adr/0011-secret-source-by-consumer.md`。占位符 `{{ sops.wifi.main.ssid }}` 取 yaml 里的 `.wifi.main.ssid`，必须是整个值；`just router::*` 用 `sops -d` 解密到临时目录，由 `render.jq` 展开，退出即删；仓库与 Nix store 里只有占位符。sops 文件路径取自 uci 包的 `passthru.sopsFile`（`nix eval --raw .#<机器>-uci.sopsFile`，即 flake.lock 里 secrets 输入的 `sops/secrets/hosts/<机器>.yaml`）。往 yaml 里新增值时用 `sops` 直接编辑，不要经过会话输出

## 非 UCI 文件

`uci.files` 把文件写成给定内容，只写不删，写入后不校验也不重载服务。每个这样的文件都要在 `just/router.just` 的 `push` 里补上校验与生效，当前有 BIRD 与 Avahi。核对文件内容用 `jq -j` 取内容再算校验和，`-r` 会多补一个换行

## 声明之外的东西

下面这些不在声明里，设备重建时不会跟着回来：

- `system`（时区、NTP、日志）、`sysctl` 的本地设置（`/etc/sysctl.d/50-local.conf`）
- LuCI 与主题类配置：argon 安装时自己设为默认主题

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

- `default.nix`：用 mise 安装 nuci，版本读自 flake 输入 `openwrt-nix` 的 `Cargo.toml`，编译声明的 Nix 模块与执行它的二进制同版本；为每台 `type = "openwrt"` 的机器产出 `<机器>-uci` 包；机器表有 `firmware` 字段时另产出 `<机器>-firmware`（固件定义转 JSON）
- `acceptance`：`run` 经 SSH 只读采集路由器状态（sysfs、logread、dmesg、iw，不依赖 ethtool），在有线主机起一次性 `iperf3 -s -1` 测双向吞吐；`diff` 并排打印，有变化的项标 `*`
- `asu`：把 `<机器>-firmware` 与 `<机器>-uci` 的 `packages` 合成 ASU 请求，轮询、下载、校验 sha256、写锁文件、清理旧镜像；版本校验在本地对照 manifest，不用 ASU 的 `packages_versions`（它会把列出的包都当作要装的包）
- `uci2nix`：经 `ubus call uci get` 取 JSON，jq 转成 nuci 结构，由 `nix eval` 打印成 Nix
- `mask.jq`：从未展开的声明里找出写了 `{{ sops.… }}` 的位置，生成输出打码规则
- `render.jq`：把 `{{ sops.<路径> }}` 展开成 sops 解密出的值，缺值或格式不对时报错
- 升级 nuci：改 `flake.nix` 里 `openwrt-nix` 的 tag，再 `nix flake lock --update-input openwrt-nix`
- 路由器不是 Nix 系统，`lib/default.nix` 的 `calcUniformSchedule` 按机器表的 `type` 把它排除在备份排程之外

## 设计决策

每节记录为什么这样设计和考虑过的替代方案。机制本身与代价见上文各节

### 用 nuci 声明，配置只在本仓库下发

路由器的 UCI 配置、少数非 UCI 文件与软件包都在 `hosts/router-mine/` 声明，由 nuci 对比差异后下发。DNS、BIRD、Avahi 原先在 home-ops 下发，已迁到这里（home-ops 的 ADR-0009、ADR-0010）

- **dewclaw**：整文件替换，没有差异预览，会删掉不在保留列表里的 `/etc/config` 文件，LuCI 里拨的开关和未声明的段都会丢
- **Ansible `community.openwrt`**：能满足需求，但要维护 playbook 与「删除」的墓碑项，不是声明式
- **LuCI 手工加脚本**：无法审查，也无法在换设备时复现
- **配置分在 home-ops 与本仓库两处下发**：同一台路由器有两个所有者，换设备要两处重建

### 机密值走 sops 占位符，由部署机渲染

声明里只写 `{{ sops.<路径> }}` 占位符，下发时在临时目录展开，见「数据放哪」。值放哪由 ADR 0011 决定：路由器无人值守时需要这些值，所以放 secrets.nix 而不是 1Password

- **nuci 自带的 sops 支持**：未采用。渲染与失败路径、`preview` 的打码都在本仓库的 `just/router.just`、`render.jq`、`mask.jq`，一处可查
- **继续用 `op inject`**：路由器的配置在无人值守的部署路径上依赖 1Password 会话，违背 ADR 0011

### 固件用 ImmortalWrt，经 ASU 云端构建

argon 主题与 `luci-app-zerotier` 是必需的，只有 ImmortalWrt 的源里都有。它的分支每天合并 OpenWrt 源码，mt76 驱动与 mt7915 固件和同期 OpenWrt 是同一提交。镜像由它的 ASU（官方 ImageBuilder 的按需构建服务）生成，不用本地 x86 环境。代价：正式版约两个月一发，内核小版本落后 OpenWrt；ASU 服务器偶发 502 与内部故障

- **OpenWrt 官方**：没有 argon 与 `luci-app-zerotier`；官方 ASU 拒绝外部源（`Repository not allowed`），只能刷完再装，镜像与锁文件就覆盖不到全部包
- **Kwrt（openwrt.ai）**：同样是云端 ImageBuilder，但包不校验签名（`CONFIG_SIGNED_PACKAGES=n`），软件源不分小版本滚动更新，没有公开 API
- **ImageBuilder 本地构建（如 nix-openwrt-imagebuilder）**：只提供 x86_64-linux 二进制，在 Apple Silicon 上要跨架构模拟
- **路由器上的 owut**：按设备上已装的包生成请求，包列表不来自本仓库
- **路由器上 `apk upgrade`**：OpenWrt 明确不支持，见「固件」

### LuCI 的 Web 服务器用 uhttpd

LuCI 页面慢在 `/ubus` 后端调用（单个 0.8～1.2 秒，rpcd 加 MT7621 的 CPU），与 Web 服务器无关。2026-11 在 CR6606 上用同一套 LuCI 与会话对比，HTTP 访问、无头 Chrome 冷热各 3 次，uhttpd 全部更快：页面 HTML 快 35～45%（LuCI 在 uhttpd 进程内执行，nginx 每个请求经 uwsgi fork 一次 CGI），整页完成快 8～17%

- **nginx（`luci-nginx`）**：多约 20 MB 常驻内存，多出 nginx-ssl-util、uwsgi 两层组件；OpenWrt 25.12 分支的 nginx 停在 1.26.3，上游已停止维护该分支。并行 TLS 握手的优势只在 HTTPS 下有意义，LuCI 平时走 HTTP
- **调大 uhttpd 的 `max_requests`**：不可行，大于 1 时并发请求会挂起（luci#9091）
