#############################################################
#
#  晶晨引导链需要放在 FAT 分区根目录的文件
#
#  厂商 u-boot（Android 那份，在 eMMC 开头，不动它）开机按 env 依次找：
#    SD 卡 / U 盘的 s905_autoscript → eMMC 第 1 分区的 emmc_autoscript
#  脚本只做一件事：把主线 u-boot（u-boot.ext / u-boot.emmc）读进内存并跳过去。
#  主线 u-boot 自带 distro boot，按 usb0 → mmc0 → mmc1 的顺序找 extlinux/extlinux.conf，
#  NixOS 的 generic-extlinux-compatible 就从这里接手。
#
#  aml_autoscript 只在全新的盒子上用一次（插卡后按住 AV 口里的复位键开机），
#  把上面的查找顺序写进厂商 env；刷过 ImmortalWrt（ophub 打包）的盒子已经写过了。
#
#  .cmd 源文件改自 ophub/amlogic-s9xxx-armbian 的 bootfs，去掉了 Android 双系统切换与
#  旧内核直接 booti 的回退分支（5.10 以后的内核厂商 u-boot 起不来）。
#
#############################################################
{
  runCommand,
  fetchurl,
  ubootTools,
}:
let
  # 主线 u-boot（X96 Max+ 的 defconfig，ophub 给 HK1 用的同一份 overload）：
  # boot_targets = usb0 mmc0 mmc1 …，bootcmd = distro_bootcmd，认 extlinux。
  # ophub/u-boot 整个仓库约 1.3 GiB 二进制，只取这一个文件，所以不按 ADR 0006 做 flake input，
  # 直接钉 commit 用 fetchurl。
  ubootOverload = fetchurl {
    url = "https://raw.githubusercontent.com/ophub/u-boot/5bf7380c25a22e889b78b4b670928272421cd6a9/u-boot/amlogic/overload/u-boot-x96maxplus.bin";
    hash = "sha256-K8FUcNg/nk50j2KJegs/cfiW2lG/QVkaA+68KJ7nA9w=";
  };
in
runCommand "hk1box-bootfs" { nativeBuildInputs = [ ubootTools ]; } ''
  mkdir -p $out
  # 厂商 u-boot 的 autoscr 只认 legacy script 镜像；架构写 arm 与 ophub 的成品一致
  for s in aml_autoscript s905_autoscript emmc_autoscript; do
    mkimage -A arm -O linux -T script -C none -n "$s" -d ${./boot}/$s.cmd $out/$s
  done
  # 同一个文件两个名字：SD/U 盘上叫 u-boot.ext，eMMC 上叫 u-boot.emmc（与 ophub 约定一致）
  install -m 0644 ${ubootOverload} $out/u-boot.ext
  install -m 0644 ${ubootOverload} $out/u-boot.emmc
''
