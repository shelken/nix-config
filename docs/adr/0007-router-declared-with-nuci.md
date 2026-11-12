# 路由器用 nuci 声明式管理，秘密走 1Password

日期: 2026-11-13

主路由（OpenWrt 衍生固件）的 UCI 配置、少数非 UCI 文件与软件包，由本仓库的 `hosts/router-mine/` 声明，用 [nuci](https://github.com/lonerOrz/openwrt-nix) 对比差异并下发，入口是 `just router::preview` 与 `just router::push`（用法见 `modules/features/network/openwrt/README.md`）。机器表里 `type = "openwrt"` 的机器不是 Nix 系统，只产出 `<机器>-uci` 编译结果。声明里的秘密与设备标识（WiFi 密码、ZeroTier 密钥、MAC 等）写成 `{{ op://Personal/router-mine/<分组>/<字段> }}`：下发时在临时目录用 `op inject` 展开，仓库与 Nix store 里只有引用；`preview` 的输出按声明里引用的位置打码。

## 考虑过的替代方案

- **dewclaw**：整文件替换，没有差异预览，会删掉不在保留列表里的 `/etc/config` 文件，LuCI 里拨的开关和未声明的段都会丢
- **Ansible `community.openwrt`**：能满足需求，但要维护 playbook 与「删除」的墓碑项，不是声明式
- **LuCI 手工 + 脚本**：无法审查，也无法在换设备时复现
- **nuci 自带的 sops 支持**：每台操作机都要带 age 密钥；本仓库的其他外部秘密（如 singbox 配置）已经用 `op://` 引用，沿用同一套
- **配置分在 home-ops 与本仓库两处下发**：同一台路由器有两个所有者，换设备要两处重建。DNS、BIRD、Avahi 原先在 home-ops，已迁到这里（home-ops 的 ADR-0009、ADR-0010）

## 后果

- nuci 对 `uci.files` 只写文件，不校验也不重载服务。`just router::push` 在下发后补上：`bird -p` 通过才 `birdc configure`，Avahi 配置变化才重启
- 声明了的文件要写全：声明里没写的选项与具名段会被删。匿名段按位置对比，列表里新增或移动条目会让 `preview` 出现一次序号噪声，下发后消失；核对时用按内容对比，不看序号
- nuci 的看门狗只在 UCI 写入中途失败时回滚，重载后断网不回滚：改 `network`、`firewall`、`wireless` 前要有不经这条链路的登录方式。热点中继在 LuCI 里开启时，声明里它是关闭的，`push` 会拒绝下发
- `diff` 会原样打印路由器上现有的值，包括被删除的秘密：`preview` 与 `push` 必须经打码，直接跑 `nuci diff` 会泄漏
- `preview`、`push` 需要 `op` 已授权（Touch ID），未授权时会超时失败
- 段与规则的 `name` 只用 ASCII：nuci 解析设备输出时把非 ASCII 的值按字节转字符，`preview` 会永远多出一条变更
- 机型相关的值（射频的硬件路径、口名）集中在 `hosts/router-mine/hardware.nix`，换路由器只改它
- 没有声明的东西不会被管理，也不会随设备重建：固件自带配置、LuCI 与 nginx、已停用的 passwall 与 shadowsocks 残留、`system`、`sysctl`，以及 home-ops 的 homepage 路由器小组件依赖的 rpcd ACL 文件 `/usr/share/rpcd/acl.d/homepage.json`（靠 `/etc/sysupgrade.conf` 保留，home-ops 改读 Prometheus 之前一直需要）
