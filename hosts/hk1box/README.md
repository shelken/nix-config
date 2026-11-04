# hk1box：ImmortalWrt → NixOS 切换手册

HK1 Box（Amlogic S905X3，4G 内存，千兆网口）当单臂旁路由，只跑 sing-box，不用 WiFi。原先刷的是 ImmortalWrt

**先用 U 盘试机，eMMC 上的 ImmortalWrt 保留到确认 NixOS 能用为止。**eMMC 现已装 NixOS，动手前的备份见 §3

## 组成

- `default.nix`：主机名、静态网络（地址取自 `vars/networking.nix`）、转发与 sysctl、防火墙、sops
- `sing-box.nix`：sing-box 服务、TUN 入站放行与订阅拉取
- `hardware.nix`：内核参数、设备树编译、initrd 驱动、extlinux 与晶晨引导文件的安装
- `bootfs.nix` + `boot/*.cmd`：厂商 u-boot 要读的 autoscript 与主线 u-boot（`u-boot.ext` / `u-boot.emmc`）
- `disk.nix`：eMMC 的 MBR 分区，前 68MiB 留给厂商 bootloader
- `image.nix`：U 盘 / SD 卡试机镜像（镜像变体 `hk1box-usb`）
- `dts/meson-sm1-hk1box-vontar-x3.dts`：设备树源码，取自 [unifreq/linux-6.12.y](https://github.com/unifreq/linux-6.12.y) 的 `d23ed3d1`，许可证见文件头（GPL-2.0+ OR MIT），未修改

## 引导链

```
厂商 u-boot（eMMC 开头，不动）
  └─ env 里的 start_autoscript：SD 卡 → U 盘 → eMMC，依次找 autoscript
       ├─ SD/U 盘 p1：s905_autoscript → 读 u-boot.ext 并跳过去
       └─ eMMC  p1：emmc_autoscript  → 读 u-boot.emmc 并跳过去
            └─ 主线 u-boot：boot_targets 先 U 盘再 eMMC，找 extlinux/extlinux.conf
                 └─ NixOS（extlinux 菜单里有最近 5 代）
```

- NixOS 靠 extlinux，厂商 u-boot 不认，要经主线 u-boot 这一跳
- 厂商 env 里需要有 `start_autoscript` / `start_emmc_autoscript`，系统内看不到。缺了拔掉 U 盘起不来：第一跳只能借 U 盘 p1 的 `s905_autoscript`，主线 u-boot 起来后才轮到 eMMC 的 `emmc_autoscript`
- env 缺失时：插 U 盘，牙签按住 AV 孔里的复位键通电，厂商 u-boot 会执行 U 盘 p1 的 `aml_autoscript`，`setenv` 后 `saveenv`（见 `boot/aml_autoscript.cmd`）。一次性动作，刷过 ophub ImmortalWrt 的盒子通常已写过
- 主线 u-boot 按 `usb0 → mmc0 → mmc1` 找 `extlinux/extlinux.conf`，U 盘 p1 有可用 extlinux 就从 U 盘起，否则落 eMMC。装好 eMMC 后拔掉 U 盘才保证进 eMMC；插 U 盘进系统是 eMMC 起不来时的救援方式

## 前置一：路由器用的订阅 URL

mac / ios / router 三份 yaml 由 `singbox-config` 生成：模板与 1Password 引用在 `modules/features/network/singbox-config/`，订阅服务地址取 sops 的 `main-domain`

白名单设备的源 IP 直接写在 `templates/router.yaml` 的 DNS 与 route 两处列表，与 `vars/networking.nix` 同一网段。改名单改这两处，再生成订阅 URL

### DNS 归属与放行

底模只留与部署无关的策略，本网解析器地址、放行（不被改写）的解析器清单、白名单三项与 clash API 的监听地址都由 `templates/router.yaml` 的 overlay 提供：

| overlay 内容                    | 作用                                                                                                                                                                                                                                                                                                           |
| :------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `dns.servers` 的 `dns-lan`      | 本网解析器，填主路由地址。底模的路由变体用空集弃用了 `type: local` 的定义（它对 `*.local` 固定走内置 mDNS），地址只能由这里给；底模的 `Lan-dns`、`local` / `lan` / `home.arpa`、`MyDirect-dns`、`clash_mode: direct`、`PTR` 五处 DNS 规则与 `route.default_domain_resolver` 都指向这个 tag，缺了配置直接起不来 |
| `clash_api.external_controller` | 底模与 Mac 一致只监听 `127.0.0.1:9090`，对局域网监听的地址由这里覆盖                                                                                                                                                                                                                                           |
| `route.rules` 的放行解析器规则  | 发往清单内解析器的查询不进本机 DNS，由内核直接放行；该解析器对内网域的负向应答不再被本机改写                                                                                                                                                                                                                   |
| 白名单                          | 名单外设备的连接在 `auto_redirect` 预匹配阶段被旁路，由内核直接转发，不进 sing-box                                                                                                                                                                                                                             |

部署域 `int.ooooo.space` 不再需要固定应答：它已登记在 proxy 仓库的 `config/rules/custom/MyDirect.yaml`（覆盖 `ooooo.space` 全部子域），随底模的 `MyDirect-dns → dns-lan` 交给主路由 dnsmasq 应答，与主路由上的固定租约天然一致。已在局域网内实测前提成立：`dig @192.168.6.1 cpa.int.ooooo.space A` → `192.168.69.46`，`dig @192.168.6.1 int.ooooo.space` → 无应答（与底模那两条规则的效果一致）；不成立时按 ADR-0012 的回退把 `modules-router/10-dns-deployment.json` 换回那两条规则

`route.rules` 的三条顺序固定为「放行解析器 → 53 劫持 → 白名单 `bypass`」：第一条要给设备显式指定的解析器留出口，白名单那条匹配的是「不在名单里」的整台设备，换序会把名单外设备的 DNS 一起放走。

改模板后先 `just hm`，让已安装的生成器指向新模板，再生成：

```bash
singbox-config router
```

- 名单外设备在 `auto_redirect` 预匹配阶段被 `bypass`，内核直接转发给主路由，不进 sing-box
- 名单内设备的网关指向这台，可使用盒子 DNS 或经盒子访问公网 DNS；发给主路由的 DNS 查询不在本方案接管范围内
- DNS 白名单按源 IP 匹配，名单外设备即使把 DNS 指向盒子，也不会拿到盒子的 fakeip
- 手机等设备开随机 MAC 不影响识别；白名单按 IP 匹配，需在主路由给设备配固定租约

改名单或上面前三项后重新生成订阅 URL，再按下一节更新 sops 中的 `sing-box-sub-url`

## 前置二：secrets 仓库

与 vps-cc 一样走系统层 sops（`docs/adr/0005-server-role-and-core-baseline.md`），步骤见 `docs/user-guide/05-vps.md` 的「主机自己的 age 密钥和口令密文」：

1. `age-keygen -o hk1box-age.txt`，私钥不进任何仓库
2. `.sops.yaml` 加一条 `sops/secrets/hosts/hk1box\.yaml$`，接收方是管理员公钥加这台的公钥
3. 新建 `sops/secrets/hosts/hk1box.yaml`，写一个键 `sing-box-sub-url`，值是上一节的订阅 URL
4. 推送后回本仓库 `just upp secrets`

这个文件不存在时正式系统无法求值，试机镜像不读它。更换 URL 并部署后不会自动重拉，需手动执行：

```bash
ssh root@hk1box systemctl start sing-box-sub-update
ssh root@hk1box journalctl -u sing-box-sub-update -n 20
```

## 1. 构建并写 U 盘

在 Mac 上（linux-builder 原生构建 aarch64）：

```bash
git add hosts/hk1box
nix build .#nixosConfigurations.hk1box.config.system.build.images.hk1box-usb
nix shell nixpkgs#zstd -c zstd -d result/sd-image/hk1box-usb*.img.zst -o hk1box-usb.img
# 确认 U 盘是哪块盘再写，写错会抹掉别的盘
diskutil list
diskutil unmountDisk /dev/diskN
sudo /bin/dd if=hk1box-usb.img of=/dev/rdiskN bs=4m   # 用系统自带 BSD dd；写的过程中按 Ctrl-T 看进度
```

首次开机会自动把根分区扩满整个 U 盘。SD 卡同样可用

## 2. U 盘试机

断电，插 U 盘（USB 2.0 口更稳），通电。镜像用的是同一个静态地址，ImmortalWrt 此时没在跑，不会冲突

```bash
ssh root@hk1box
nixos-version
cat /proc/device-tree/model          # HK1 Box/Vontar X3
ip -br addr show eth0                # 地址正确、UP
cat /sys/class/net/eth0/address      # 应为 default.nix 里钉住的 00:e5:00:00:15:eb
cat /sys/class/net/eth0/speed        # 1000
lsblk                                # mmcblk? 是 eMMC，sd? 是 U 盘
ls -l /dev/disk/by-path/ | grep ffe07000   # disk.nix 用的就是它
reboot                               # 能再次进来
```

- MAC 对不上（这台 efuse 为空，u-boot 会按 SoC 派生一个稳定但不同的值）：钉它的地方就是 `default.nix` 里的 `networking.interfaces.eth0.macAddress`，别去改 `dts/` —— u-boot 在启动时会把 `local-mac-address` 写进设备树，会盖掉 dts 里的值
- 起不来：接 TTL 串口（115200）看日志；卡在网口就把 `dts/` 里的 `phy-mode` 换成注释中的 `rgmii-txid` 那组
- 此时客户端网关仍指向这台，流量照常转发给主路由，只是不走代理。装 eMMC 之前拔掉 U 盘就回 ImmortalWrt

## 3. 备份 eMMC 开头

装机会重写 MBR（只动前 440 字节，这段实测为空）。动手前在 U 盘系统里备一份：

```bash
E=$(readlink -f /dev/disk/by-path/platform-ffe07000.mmc)   # 如 /dev/mmcblk1
dd if=$E of=/root/emmc-head-68M.img bs=1M count=68
# eMMC 的两个硬件引导分区，厂商 bootloader 的另一份拷贝（没有就跳过）
for p in boot0 boot1; do [ -b ${E}-$p ] && dd if=${E}-$p of=/root/emmc-$p.img; done   # by-path 的写法是 <E>-boot0
```

然后 `scp` 回 Mac 保存。eMMC 起不来时，插 U 盘进系统 `dd` 写回前 68MiB 即可

## 4. 装进 eMMC

目标是正在跑的 U 盘系统，已经是 NixOS，跳过 kexec 直接分区安装。随装目录只放 age 私钥，目录结构就是目标路径（`$EXTRA/var/lib/sops-nix/key.txt` → 装完系统的 `/var/lib/sops-nix/key.txt`）：

```bash
EXTRA=$(mktemp -d)
install -d -m 700 "$EXTRA/var/lib/sops-nix"
install -m 400 hk1box-age.txt "$EXTRA/var/lib/sops-nix/key.txt"

# 先确认 disko 会挂出什么
nix eval .#nixosConfigurations.hk1box.config.fileSystems --apply 'fs: builtins.mapAttrs (_: v: v.device) fs'

nixos-anywhere -f .#hk1box --target-host root@hk1box --build-on local \
  --phases disko,install --extra-files "$EXTRA"
```

装完**先别重启**，确认私钥进了新根（`--extra-files` 拿到空值时是静默跳过拷贝的，安装照样报成功）：

```bash
ssh hk1box 'ls -l /mnt/var/lib/sops-nix/key.txt'   # 应为 -r-------- 400，约 189 字节
```

缺了就补（`/mnt` 这时还挂着新根，不用重装）：

```bash
scp hk1box-age.txt hk1box:/mnt/var/lib/sops-nix/key.txt
ssh hk1box 'chmod 400 /mnt/var/lib/sops-nix/key.txt'
```

### 别在 U 盘系统上跑 deploy / nixos-rebuild

试机镜像的 `/boot` 沿用主机配置指向 eMMC 的 p1（`image.nix` 没覆盖 loader 那侧的 `fileSystems`），应挂 U 盘自己的 `sda1`。所以在**U 盘系统**上激活一次带 sops 的主机配置（`just deploy hk1box`、`nixos-rebuild switch`），就会：

- 按 **U 盘 store** 的路径重写 eMMC 的 `/boot/extlinux/extlinux.conf`
- 删掉 eMMC 自己系统的 initrd（它判定「不再需要」）
- 自己还在 sops 那步失败（U 盘系统里没有这台机器的 age 私钥），deploy-rs 回滚

结果是拔盘后 eMMC 起不来，中招后这样修（用 eMMC 自己的系统重写引导项）：

```bash
ssh hk1box 'nixos-enter --root /mnt -c "/nix/var/nix/profiles/system/bin/switch-to-configuration boot"'
ssh hk1box 'grep -E "^DEFAULT|init=" /mnt/boot/extlinux/extlinux.conf'   # init 应指向 eMMC store 里的那份
```

装完 eMMC 的顺序是：**断电 → 拔 U 盘 → 通电**（通电那一刻 U 盘不能在，u-boot 先找它）

## 5. 验证

```bash
ssh root@hk1box
findmnt -no SOURCE / /boot           # /dev/mmcblk1p2、/dev/mmcblk1p1
readlink /run/current-system         # 名字里没有 sd-card；有的话说明进的是 U 盘试机镜像
cat /sys/class/net/eth0/address      # 00:e5:00:00:15:eb
ls /boot                             # emmc_autoscript u-boot.emmc extlinux nixos
ls /run/secrets/                     # 有 sing-box-sub-url（sops-nix 是 oneshot，is-active 显示 inactive 属正常）
ls -l /etc/sing-box/config.json      # 软链到 /var/lib/sing-box-sub/config.json
systemctl is-active sing-box         # active
nft list tables                      # 有 sing-box 自己的表
```

首次开机 sing-box 会失败重启几次：`sing-box-sub-update.timer` 要开机 1 分钟（外加最多 10 分钟随机延迟）才拉订阅，配置就位前 sing-box 起不来。等一会儿再确认；一直不 active 就手动拉一次：

```bash
ssh root@hk1box systemctl start sing-box-sub-update
ssh root@hk1box systemctl status sing-box --no-pager | head -12
```

机器没有 RTC，开机头几分钟墙钟可能是垃圾值，NTP 到位后才准，那期间 `uptime` 读数离谱属正常

白名单内的设备走一遍代理，neko-master 能看到流量；名单外的设备照常上网，且不出现在 sing-box 的连接列表里

## 日常更新

**只在 eMMC 系统上 deploy**（先 `findmnt -no SOURCE /` 确认是 `/dev/mmcblk1p2`；跑在 U 盘系统上会写坏 eMMC 的 `/boot`，见 §4）：

```bash
just deploy hk1box
```

deploy-rs 有自动回滚：新配置把网络弄断、30 秒内确认不了就退回上一代。重启后回不来时，插 U 盘救援，或接串口在 extlinux 菜单选上一代
