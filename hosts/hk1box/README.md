# hk1box：ImmortalWrt → NixOS 切换手册

HK1 Box（Amlogic S905X3，4G 内存，千兆网口），在家里当单臂旁路由，只跑 sing-box，不用 WiFi。原先刷的是 ImmortalWrt（armsr rootfs 经 ophub 打包），现在换成本仓库的 `hk1box`

**先用 U 盘试机，eMMC 上的 ImmortalWrt 一直保留到你确认 NixOS 能用为止。**

## 组成

- `default.nix`：主机名、静态网络（地址取自 `vars/networking.nix`）、转发与 sysctl、防火墙、sops 文件
- `sing-box.nix`：sing-box 服务，以及从订阅服务定时拉取配置
- `hardware.nix`：内核参数、设备树编译、initrd 驱动、extlinux 与晶晨引导文件的安装
- `bootfs.nix` + `boot/*.cmd`：厂商 u-boot 要读的 autoscript 与主线 u-boot（`u-boot.ext` / `u-boot.emmc`）
- `disk.nix`：eMMC 的 MBR 分区，前 68MiB 留给厂商 bootloader
- `image.nix`：U 盘 / SD 卡试机镜像（nixpkgs 镜像变体 `hk1box-usb`），同一份配置，不跑 sing-box
- `dts/meson-sm1-hk1box-vontar-x3.dts`：设备树源码，取自 [unifreq/linux-6.12.y](https://github.com/unifreq/linux-6.12.y) 的 `d23ed3d1`（ophub 内核用的同一份），许可证见文件头（GPL-2.0+ OR MIT），未修改

## 引导链

```
厂商 u-boot（eMMC 开头，不动）
  └─ env 里的 start_autoscript：SD 卡 → U 盘 → eMMC，依次找 autoscript
       ├─ SD/U 盘 p1：s905_autoscript → 读 u-boot.ext 并跳过去
       └─ eMMC  p1：emmc_autoscript  → 读 u-boot.emmc 并跳过去
            └─ 主线 u-boot：boot_targets = usb0 mmc0 mmc1 …，找 extlinux/extlinux.conf
                 └─ NixOS（extlinux 菜单里有最近 5 代）
```

- 这台盒子现在**没有走主线 u-boot**：eMMC p1 里没有 `u-boot.emmc`，`extlinux/` 下只有一个 `extlinux.conf.bak`，而 `boot.ini`、`boot.scr`、`uEnv.txt`、`zImage` 都在 —— 也就是厂商 u-boot 直接 `booti` 起了 6.12.93-ophub。换主线 u-boot 的理由只有一个：**NixOS 用 extlinux，厂商 u-boot 不认**（它认的是 `boot.ini` / `boot.scr` + `uEnv.txt` 这套脚本）
- 「厂商 u-boot 起不来 5.10 以后的内核」不成立：它现在跑的就是 6.12.93（`zImage` 自解压）。经主线 u-boot 这一跳是 ophub / flippy 的通行做法，但**在这台盒子上从未真正执行过**（所以第一次装完能不能起，属于试机要验证的事）
- 整条链成立的前提是厂商 env 里有 `start_autoscript` / `start_emmc_autoscript`。这个 env 从系统内看不到（不在 eMMC 前 2 MB，也没有 `fw_printenv`），所以**试机起不来时，第一步就是重写它**：插上 U 盘，用牙签按住 AV 孔里的复位键再通电，等它自动重启
- 主线 u-boot 先找 U 盘、SD 卡，再找 eMMC，所以插着 U 盘就从 U 盘起，拔掉就回 eMMC。这也是之后的救援方式

## 前置一：路由器用的订阅 URL

sing-box 配置走和 Mac / iOS 一样的链路：Mac 上的 sbtools 把 yaml 加密成订阅 URL，订阅服务按 URL 现场装配。路由器单独一份 yaml（如 `~/.config/sing-box/router.yaml`，只在本机），底模用 proxy 仓库的 `template-router.json`（tun 开 `auto_redirect`、53 端口的 DNS 入口、clash API 对局域网监听）：

```yaml
subs:
  - https://<机场订阅>
template_url: https://raw.githubusercontent.com/shelken/proxy/main/config/sing-box/template-router.json
overlay: |
  {
    "experimental": { "clash_api": { "secret": "<随机串，neko-master 用同一个>" } },
    "dns": { "rules": [
      { "source_mac_address": ["<MAC1>", "<MAC2>"], "invert": true, "server": "dns-local-system" }
    ] },
    "route": { "rules": [
      { "type": "logical", "mode": "and", "rules": [
          { "inbound": ["tun-in"] },
          { "type": "logical", "mode": "and", "invert": true,
            "rules": [ { "source_mac_address": ["<MAC1>", "<MAC2>"] } ] }
        ],
        "action": "bypass", "outbound": "direct" }
    ] }
  }
```

```bash
sbtools check -c ~/.config/sing-box/router.yaml
sbtools encode -s https://<订阅服务> -c ~/.config/sing-box/router.yaml   # URL 进剪贴板
```

白名单写在 overlay 里，随载荷加密，不出现在任何仓库的明文中。规则含义见 proxy 仓库的路由器用户指南；要点：

- 名单外的设备在 `auto_redirect` 的预匹配阶段被 `bypass`，内核直接转发给主路由，不进 sing-box；`outbound: direct` 是兜底
- `invert` 反转的是**整条规则**的所有条件，所以「排除白名单」要写成两层：外层 AND 限定 `inbound: tun-in`，内层只反转 MAC。把 `invert` 与 `inbound` 写在同一层的话，`dns-in` 进来的查询（它不满足 `tun-in`，整条为假）会被翻成命中，又被 `direct` 送回本机 53 端口绕成环，同时白名单设备的 DNS 也拿不到 fakeip
- 名单外的设备如果 DNS 也指向这台，拿到的是真实 IP 而不是 fakeip
- 名单内的设备，网关与 DNS 都要指向这台（主路由 DHCP 下发，或设备上手动设）；DNS 指向主路由时查询在同网段直达，fakeip 用不上
- 手机要把这个 Wi-Fi 的「私有地址」改成固定，否则 MAC 会变

改名单就改 overlay，重新 `encode`，再按下一节更新 sops 里的 URL

## 前置二：secrets 仓库

与 vps-cc 一样走系统层 sops（`docs/adr/0005-server-role-and-core-baseline.md`），步骤见 `docs/user-guide/05-vps.md` 的「主机自己的 age 密钥和口令密文」：

1. `age-keygen -o hk1box-age.txt`，私钥不进任何仓库
2. `.sops.yaml` 加一条 `sops/secrets/hosts/hk1box\.yaml$`，接收方是管理员公钥加这台的公钥
3. 新建 `sops/secrets/hosts/hk1box.yaml`，写一个键 `sing-box-sub-url`，值是上一节的订阅 URL（它能换出完整节点配置，等同凭据）
4. 推送后回本仓库 `nix flake update secrets`

这个文件不存在时，`hk1box` 的正式系统无法求值；试机镜像不读它

拉取由 `sing-box.nix` 负责：开机一次、之后每 6 小时一次，先 `sing-box check`，内容变了才替换并重启；失败时保留上一份。部署本身不会触发拉取，换了 URL 部署后手动执行一次：

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
sudo dd if=hk1box-usb.img of=/dev/rdiskN bs=4m status=progress
```

首次开机会自动把根分区扩满整个 U 盘。SD 卡同样可用（`mmc0` 比 eMMC 先被找到）

这是 nixpkgs 的镜像变体机制（`image.modules` → `system.build.images`），在 Linux 上也可以用 `nixos-rebuild build-image --image-variant hk1box-usb --flake .#hk1box`。想看变体和正式系统差在哪，读它的配置：

```bash
nix eval .#nixosConfigurations.hk1box.config.system.build.images.hk1box-usb.passthru.config.fileSystems \
  --apply 'fs: builtins.mapAttrs (_: v: v.device) fs'
```

## 2. U 盘试机

断电，插 U 盘（USB 2.0 口更稳），通电。镜像用的是同一个静态地址，ImmortalWrt 此时没在跑，不会冲突

```bash
ssh root@hk1box
nixos-version
cat /proc/device-tree/model          # HK1 Box/Vontar X3
ip -br addr show eth0                # 地址正确、UP
cat /sys/class/net/eth0/address      # 与 ImmortalWrt 时记下的 MAC 一致，不是随机值
cat /sys/class/net/eth0/speed        # 1000
lsblk                                # mmcblk? 是 eMMC，sd? 是 U 盘
ls -l /dev/disk/by-path/ | grep ffe07000   # disk.nix 用的就是它
reboot                               # 能再次进来
```

此时客户端网关仍指向这台，流量照常转发给主路由，只是不走代理。起不来就拔掉 U 盘，回到 ImmortalWrt

上面为什么要单独看 MAC：这台盒子的 efuse 是空的（`/sys/bus/nvmem/devices/efuse0/nvmem` 实测全是 0），dts 里的 `nvmem-cells = <&eth_mac>` 读不到东西，MAC 只能靠引导链写进设备树。换了内核又换了 u-boot 之后这一步可能不再发生，内核就会随机取一个 MAC；真随机了，就在 `dts/` 的 `&ethmac` 里补一条 `local-mac-address`，或让主线 u-boot 的 env 带上 `ethaddr`

起不来时接 TTL 串口（115200）看日志。如果卡在网口，多半是 PHY 的 rgmii 延时：在 `dts/` 里换成文件中注释掉的 `rgmii-txid` 那组

## 3. 备份 eMMC 开头

装机会重写 MBR（清零前 440 字节；实测这台的 sector 0 只有分区表，前 440 字节全 0，bootloader 数据从约 29 KiB 处才开始，所以不受影响）。动手前在 U 盘系统里备一份：

```bash
E=$(readlink -f /dev/disk/by-path/platform-ffe07000.mmc)   # 如 /dev/mmcblk1
dd if=$E of=/root/emmc-head-68M.img bs=1M count=68
# eMMC 的两个硬件引导分区，厂商 bootloader 的另一份拷贝（没有就跳过）
for p in boot0 boot1; do [ -b ${E}$p ] && dd if=${E}$p of=/root/emmc-$p.img; done
```

然后 `scp` 回 Mac 保存。万一 eMMC 起不来：插 U 盘进系统，`dd` 写回前 68MiB 即可

## 4. 装进 eMMC

目标就是正在跑的 U 盘系统，已经是 NixOS，所以跳过 kexec，直接分区安装。随装目录只放 age 私钥：

```bash
mkdir -p /tmp/hk1box-extra/var/lib/sops-nix
cp hk1box-age.txt /tmp/hk1box-extra/var/lib/sops-nix/key.txt
chmod 600 /tmp/hk1box-extra/var/lib/sops-nix/key.txt

# 先确认 disko 会挂出什么
nix eval .#nixosConfigurations.hk1box.config.fileSystems --apply 'fs: builtins.mapAttrs (_: v: v.device) fs'

nixos-anywhere -f .#hk1box --target-host root@hk1box --build-on local \
  --phases disko,install --extra-files /tmp/hk1box-extra
```

装完拔掉 U 盘再 `ssh root@hk1box reboot`（插着会继续从 U 盘起）

## 5. 验证

```bash
ssh root@hk1box
findmnt / /boot                      # eMMC 的 p2、p1
ls /boot                             # emmc_autoscript u-boot.emmc extlinux nixos
systemctl status sing-box-sub-update sing-box
ls -l /etc/sing-box/config.json      # 软链到 /var/lib/sing-box-sub/config.json
nft list tables                      # 有 sing-box 自己的表
```

白名单内的设备走一遍代理，neko-master 能看到流量；名单外的设备照常上网，且不出现在 sing-box 的连接列表里

## 日常更新

```bash
just deploy hk1box
```

deploy-rs 有自动回滚：新配置把网络弄断、30 秒内确认不了就退回上一代。重启后回不来时，插 U 盘救援，或接串口在 extlinux 菜单选上一代
