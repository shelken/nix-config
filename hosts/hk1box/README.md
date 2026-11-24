# hk1box

HK1 Box（Amlogic S905X3，4G 内存，千兆网口）单臂旁路由，只跑 sing-box，eMMC 已装 NixOS。`dts/meson-sm1-hk1box-vontar-x3.dts` 取自 [unifreq/linux-6.12.y](https://github.com/unifreq/linux-6.12.y) `d23ed3d1`（GPL-2.0+ OR MIT），未修改

## 引导入口

- 厂商 u-boot 经主线 u-boot（`usb0 → mmc0 → mmc1`）读 `extlinux/extlinux.conf` 启动 NixOS
- 装好 eMMC 后**拔掉 U 盘**才进 eMMC；eMMC 起不来时**插 U 盘**进试机镜像救援
- 厂商 env 缺 `start_autoscript` 时，插 U 盘并用牙签按住 AV 孔复位键通电，执行 `aml_autoscript` 写入 env（一次性动作）

## 订阅与 secrets

订阅 URL 由 `singbox-config router` 生成（设计见 [singbox-config](../../modules/features/network/singbox-config/README.md)），按 [VPS 指南](../../docs/user-guide/05-vps.md) 在 `secrets` 仓库创建 `sops/secrets/hosts/hk1box.yaml`，写入 `sing-box-sub-url` 键并 `just upp secrets`

更换 URL 并部署后不会自动重拉，手动触发：

```bash
ssh root@hk1box systemctl start sing-box-sub-update
ssh root@hk1box journalctl -u sing-box-sub-update -n 20
```

## 救援 U 盘与 eMMC 备份

```bash
# 构建并写入 U 盘（SD 卡同理；确认目标盘符再写）
nix build .#nixosConfigurations.hk1box.config.system.build.images.hk1box-usb
nix shell nixpkgs#zstd -c zstd -d result/sd-image/hk1box-usb*.img.zst -o hk1box-usb.img
diskutil list && diskutil unmountDisk /dev/diskN
sudo /bin/dd if=hk1box-usb.img of=/dev/rdiskN bs=4m   # Ctrl-T 看进度
```

插 U 盘（USB 2.0 口更稳）通电进试机镜像；若 MAC 不符改 `default.nix` 的 `networking.interfaces.eth0.macAddress`（不要改 `dts/`，u-boot 会覆写 `local-mac-address`）；启动失败接 TTL 串口（115200）排查。重装前备份 eMMC 前 68MiB 与硬件引导分区并 `scp` 回 Mac，eMMC 故障时插 U 盘 `dd` 写回即可：

```bash
E=$(readlink -f /dev/disk/by-path/platform-ffe07000.mmc)
dd if=$E of=/root/emmc-head-68M.img bs=1M count=68
for p in boot0 boot1; do [ -b ${E}-$p ] && dd if=${E}-$p of=/root/emmc-$p.img; done
```

## 装进 eMMC

在运行中的 U 盘系统直接走 `disko,install`（仅带 age 私钥 `$EXTRA/var/lib/sops-nix/key.txt`，权限 400）：

```bash
EXTRA=$(mktemp -d)
install -d -m 700 "$EXTRA/var/lib/sops-nix"
install -m 400 hk1box-age.txt "$EXTRA/var/lib/sops-nix/key.txt"
nixos-anywhere -f .#hk1box --target-host root@hk1box --build-on local \
  --phases disko,install --extra-files "$EXTRA"
ssh hk1box 'ls -l /mnt/var/lib/sops-nix/key.txt'   # 装完先核对私钥已写入再断电
```

`--extra-files` 拿到空路径会静默跳过拷贝，缺失时趁 `/mnt` 仍挂载直接补传并复查后再断电：

```bash
scp hk1box-age.txt hk1box:/mnt/var/lib/sops-nix/key.txt
ssh hk1box 'chmod 400 /mnt/var/lib/sops-nix/key.txt'
```

装完顺序：**断电 → 拔 U 盘 → 通电**。设备无 RTC，开机头几分钟墙钟与 `uptime` 可能异常，待 NTP 同步后恢复；`sing-box-sub-update.timer` 开机 1 分钟后（加随机延迟）才拉订阅，首次开机可手动 `systemctl start sing-box-sub-update`

### 别在 U 盘系统上跑 deploy / nixos-rebuild

试机镜像的 `/boot` 沿用主机配置指向 eMMC 的 p1，在**U 盘系统**上激活带 sops 的主机配置会按 U 盘 store 路径重写 eMMC 的 `/boot/extlinux/extlinux.conf`、删掉 eMMC 自己的 initrd 并因缺私钥回滚，导致拔盘后 eMMC 无法启动。中招后在 U 盘系统挂载新根抢救：

```bash
ssh hk1box 'nixos-enter --root /mnt -c "/nix/var/nix/profiles/system/bin/switch-to-configuration boot"'
ssh hk1box 'grep -E "^DEFAULT|init=" /mnt/boot/extlinux/extlinux.conf'   # init 应指向 eMMC store
```

## 日常更新

**只在 eMMC 系统上 deploy**（先确认 `findmnt -no SOURCE /` 为 `/dev/mmcblk1p2`）：

```bash
just deploy hk1box
```

deploy-rs 30 秒内确认失败自动回滚；重启后无法联网时插 U 盘救援，或接串口在 extlinux 菜单选上一代
