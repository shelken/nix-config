# hk1box：ImmortalWrt → NixOS 切换手册

HK1 Box（Amlogic S905X3，4G 内存，千兆网口）当单臂旁路由，只跑 sing-box，不用 WiFi。原先刷的是 ImmortalWrt

**先用 U 盘试机，eMMC 上的 ImmortalWrt 一直保留到你确认 NixOS 能用为止。**

## 组成

- `default.nix`：主机名、静态网络（地址取自 `vars/networking.nix`）、转发与 sysctl、防火墙、sops
- `sing-box.nix`：sing-box 服务与订阅拉取（开机一次，之后每 6 小时）
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

- NixOS 靠 extlinux，厂商 u-boot 不认，所以要经主线 u-boot 这一跳；这一跳在这台盒子上还没跑通过，第一次能不能起由试机验证
- 前提是厂商 env 里有 `start_autoscript` / `start_emmc_autoscript`，从系统内看不到。**起不来时第一步就重写它**：插上 U 盘，用牙签按住 AV 孔里的复位键再通电，等它自动重启
- 主线 u-boot 先找 U 盘、SD 卡，再找 eMMC：插着 U 盘就从 U 盘起，拔掉就回 eMMC。这也是之后的救援方式

## 前置一：路由器用的订阅 URL

mac / ios / router 三份 yaml 由 `singbox-config` 生成：模板与 1Password 引用在 `modules/features/network/singbox-config/`，订阅服务地址取 sops 的 `main-domain`

```bash
singbox-config router        # 填充模板 → sbtools check → encode，URL 进剪切板
```

- 白名单设备在 `auto_redirect` 预匹配阶段被 `bypass`，内核直接转发给主路由，不进 sing-box
- 名单内的设备，网关与 DNS 都指向这台；名单外的设备即使 DNS 指过来，拿到的也是真实 IP 而不是 fakeip
- 手机要把这个 Wi-Fi 的「私有地址」改成固定，否则 MAC 会变

改名单就改模板里的 MAC 条目，重新 `singbox-config router`，再按下一节更新 sops 里的 URL

## 前置二：secrets 仓库

与 vps-cc 一样走系统层 sops（`docs/adr/0005-server-role-and-core-baseline.md`），步骤见 `docs/user-guide/05-vps.md` 的「主机自己的 age 密钥和口令密文」：

1. `age-keygen -o hk1box-age.txt`，私钥不进任何仓库
2. `.sops.yaml` 加一条 `sops/secrets/hosts/hk1box\.yaml$`，接收方是管理员公钥加这台的公钥
3. 新建 `sops/secrets/hosts/hk1box.yaml`，写一个键 `sing-box-sub-url`，值是上一节的订阅 URL
4. 推送后回本仓库 `nix flake update secrets`

这个文件不存在时正式系统无法求值，试机镜像不读它。换了 URL 后手动拉一次：

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

首次开机会自动把根分区扩满整个 U 盘。SD 卡同样可用

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

- MAC 变随机了（这台 efuse 为空，MAC 全靠引导链注入）：在 `dts/` 的 `&ethmac` 里补 `local-mac-address`，或让主线 u-boot 的 env 带上 `ethaddr`
- 起不来：接 TTL 串口（115200）看日志；卡在网口就把 `dts/` 里的 `phy-mode` 换成注释中的 `rgmii-txid` 那组
- 此时客户端网关仍指向这台，流量照常转发给主路由，只是不走代理。拔掉 U 盘就回 ImmortalWrt

## 3. 备份 eMMC 开头

装机会重写 MBR（只动前 440 字节，这段实测为空）。动手前在 U 盘系统里备一份：

```bash
E=$(readlink -f /dev/disk/by-path/platform-ffe07000.mmc)   # 如 /dev/mmcblk1
dd if=$E of=/root/emmc-head-68M.img bs=1M count=68
# eMMC 的两个硬件引导分区，厂商 bootloader 的另一份拷贝（没有就跳过）
for p in boot0 boot1; do [ -b ${E}$p ] && dd if=${E}$p of=/root/emmc-$p.img; done
```

然后 `scp` 回 Mac 保存。eMMC 起不来时，插 U 盘进系统 `dd` 写回前 68MiB 即可

## 4. 装进 eMMC

目标是正在跑的 U 盘系统，已经是 NixOS，跳过 kexec 直接分区安装。随装目录只放 age 私钥：

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
