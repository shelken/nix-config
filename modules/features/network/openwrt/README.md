# openwrt

用 [nuci](https://github.com/lonerOrz/openwrt-nix) 声明式管理 OpenWrt 路由器的 UCI 配置、少数非 UCI 文件与软件包。机器表 `hosts/default.nix` 中 `type = "openwrt"` 的机器（当前是 `router-mine`）将声明放在 `hosts/<机器>/`，编译为 `uci.json` 后由 nuci 对比差异并下发。固件同样由声明生成，支持 ASU 云端与本地构建节点两条通道

可选功能，仅在 `imports` 声明的主机启用：部署机 `mio`（`self.modules.darwin.openwrt`），本地固件构建节点 `homelab-1`（`self.modules.nixos.openwrt-builder`）。升级 nuci 时改 `flake.nix` 中 `openwrt-nix` 的 tag 再运行 `nix flake lock --update-input openwrt-nix`

## 用法

所有配方见 `just --list router`（定义在 [just/router.just](../../../../just/router.just)）：

- 展开 `{{ sops.… }}` 占位符需要 `SOPS_AGE_KEY_FILE` 指向 `admin_mio` 的 age 密钥；`uci.files` 的 `content` 中的占位符不在输出打码范围
- 匿名段按位置对比，列表新增或移动条目会让 `preview` 出现一次序号噪声，下发后消失；核对一致性按段内容看，不看序号
- 下发前会检查设备上所有启用中的 `mode == "sta"` 无线段，防止误关热点中继导致断网
- 迁移新配置：`just router::import <配置>` 导出后挑出设备数据与密钥写入 `hosts/router-mine/`，把所需包写入同文件的 `uci.packages`，经 `preview` 核对后 `push`；nuci 只管声明中出现的文件，但已声明文件必须写全

## 固件

固件是版本控制的单位，发行版、内核与全部包一起替换。路由器上不跑 `apk upgrade`，原地升级会装上与内核不匹配的 kmod，只读层与 overlay 的库也会错版

常规升级流程：改 `firmware.nix` 版本或功能文件的 `uci.packages` → `just router::firmware-update`（或 `firmware-update-local`）并审查 `firmware.lock.json` diff → `just router::acceptance` 采基线 → `just router::upgrade` → 再次 `acceptance` 并用 `acceptance-diff` 对比。非显式约束与坑：

- 镜像只存本机 `${XDG_DATA_HOME:-~/.local/share}/router-firmware/<机器>/`（保留最新 3 个，锁文件指向的不删）；软件源更新后旧版无法重建，回滚依赖这些本机镜像
- 跨发行版或包管理器变更时需手动 `sysupgrade -n`（从 Kwrt 刷入还需 `-F`，因 Kwrt 自定义了 `board_name`），网线直连后运行 `just router::push root@192.168.1.1` 恢复配置，并在 LuCI 重设 root 密码（`-n` 会清空 `/etc/shadow`，保留配置刷入不会）；切勿先手动改 lan 地址，只改地址不改 DHCP 与防火墙会导致停发 IP
- 对比验收结果时，先看 `client_*` 的信道、信号与协商速率是否相近再比较吞吐数字；验收结果含设备运行数据，仅存本机镜像目录下的 `acceptance/`
- ASU 与本地 ImageBuilder 的镜像文件名与哈希规则不同，不能跨后端用 `build` 复用另一后端的锁文件，切换后端需运行对应 `update` 重写
- ASU 失败结果按请求 hash 缓存（服务端故障需等缓存过期或切换 `firmware-update-local`），镜像也按 hash 缓存在公共服务器上，因此构建请求不含机密，机密仍由 `push` 下发；版本校验在本地对照 manifest，不用 ASU 的 `packages_versions`（后者会把列出的包都当成待安装包）

## 目录与包

`hosts/router-mine/` 按功能分组，目录布局与引入原则见 [hosts/router-mine/README.md](../../../../hosts/router-mine/README.md)

包声明规则：只列功能显式需要的包，依赖由 apk 自动带入，发行版默认包不管；LuCI 包先查是否有 `luci-i18n-<名>-zh-cn`，有则只写翻译包（依赖本体，无需重复声明）；从列表移除不会卸载，卸载需写 `-包名`；无 UCI 配置的包（如 `bird2c`）与它的配置文件写在同一个 `.nix`

## 数据放哪

本仓库公开，设备运行环境数据不得进入（划分规则见 [ADR 0011](../../../../docs/adr/0011-secret-source-by-consumer.md)）：

| 内容                                   | 位置                                                                               |
| :------------------------------------- | :--------------------------------------------------------------------------------- |
| 结构与通用选项                         | `hosts/router-mine/`                                                               |
| 网段与已登记主机 IP                    | `vars/networking.nix`（`myvars.networking.hostAddress.<名>.address`）              |
| 实体设备 MAC（DHCP 静态租约）          | secrets.nix 明文 nix（k8s 节点读 `lanMac`，其余读 `dhcpMacs`）                     |
| SSID、WiFi 密码、ZeroTier 密钥与设备名 | secrets.nix 的 `sops/secrets/hosts/router-mine.yaml`，声明中写 `{{ sops.<路径> }}` |
| 对外放行规则的 IPv6 后缀               | `hosts/router-mine/home-ops/firewall.nix`（来自服务随机固定 MAC，非私密）          |

占位符必须占据整个值；往 sops yaml 新增机密时直接用 `sops` 编辑，不要经过会话输出

## 声明之外的东西

以下内容不在声明中，设备重建时不会自动恢复：`system`（时区、NTP、日志）以及 `/etc/sysctl.d/50-local.conf`

## 已知问题

- 已声明的段内漏写选项、已声明的文件内漏写具名段，以及已声明匿名类型中多出的匿名项，都会在 `push` 时被删；迁移应从 `import` 完整输出起步
- 未声明过的匿名段类型（如 LuCI 添加的静态租约 `host`）不会被删，但 `preview` 会持续提示待删除
- 在 LuCI 中修改受管文件会在下次 `push` 被覆盖
- `push` 仅在 UCI 执行中途失败或断线时 60 秒后回滚；UCI 写完后重载服务导致断网不会回滚，60 秒后备份也会被删（nuci `arm_watchdog`），改 network、firewall、wireless 前需备好替代登录链路
- `sshKeys` 整份覆盖 `authorized_keys`，部署机 ssh-agent 公钥不在列表时 nuci 会自动追加防锁死
- 含非 ASCII 字符的值会让 `preview` 永远显示待修改（nuci `split_uci_quoted` 按字节解析），下发值本身正确，规则与段 `name` 仅用 ASCII 可避开
- router-mine 的 odhcpd（2026.06.29）在 `br-lan.6` 重建后不再转发 RA，目前靠 `network/odhcpd.nix` hotplug 脚本兜底；上游已于 2026-10-28 修复（`d6c15fb`），固件含该修复后移除该文件（#369）

## 设计决策

### 用 nuci 声明，配置只在本仓库下发

原在 home-ops 下发的 DNS、BIRD、Avahi 已统一迁入本仓库（home-ops ADR-0009、ADR-0010）。放弃的方案：dewclaw（整文件替换无 diff，会删未声明 `/etc/config` 与 LuCI 开关）、Ansible `community.openwrt`（非声明式，需维护删除墓碑）、LuCI 手工加脚本（难审查复现）、跨仓库分头下发（双所有者）

### 机密值走 sops 占位符，由部署机渲染

路由器无人值守需要这些值，按 ADR 0011 放 secrets.nix 而非 1Password。放弃的方案：nuci 自带 sops 支持（渲染、失败路径与打码集中在 `just/router.just` 与 `*.jq` 更易审计）、继续用 `op inject`（依赖 1Password 会话）

### 固件用 ImmortalWrt，支持 ASU 云端与本地 x86_64 节点构建

argon 主题与 `luci-app-zerotier` 为刚需且仅 ImmortalWrt 官方源兼备，其分支每日合并 OpenWrt 源码，mt76/mt7915 与同期一致。提供 ASU 云端（省本机环境但偶发 502）与局域网 x86_64 节点本地 ImageBuilder 两条同构通道。代价：正式版约两月一发，内核小版本落后 OpenWrt

放弃的方案：OpenWrt 官方（缺所需包且官方 ASU 拒绝外部源）、Kwrt（不验包签名、无小版本、无公开 API）、Apple Silicon 本机跨架构模拟 ImageBuilder（不如局域网原生 x86_64 节点稳定）、路由器上 `owut`（包列表不源自本仓库）

### LuCI 的 Web 服务器用 uhttpd

LuCI 慢在 `/ubus` 后端调用（rpcd 加 MT7621 CPU 单个 0.8～1.2 秒），与 Web 服务器无关。2026-11 在 CR6608 上同会话无头 Chrome 冷热各 3 次对比，uhttpd 页面 HTML 快 35～45%（进程内执行，无需经 uwsgi fork CGI），整页完成快 8～17%

放弃的方案：nginx（多约 20 MB 常驻内存与两层组件，25.12 分支停在已停维的 1.26.3，并行 TLS 优势在 HTTP 下无用）；调大 uhttpd `max_requests`（大于 1 时并发请求挂起，luci#9091）
