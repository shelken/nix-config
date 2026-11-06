{ inputs, ... }:
#############################################################
#
#  eMMC 分区（nixos-anywhere 装机时由 disko 执行）
#
#  不用 modules/features/nixos/disko.nix 的现成布局：那里都是 GPT。晶晨的 bootloader
#  从 eMMC 的 LBA 1（第 512 字节）开始，GPT 头恰好也写在 LBA 1，一写就把厂商 u-boot 覆盖掉；
#  MBR 只占 LBA 0（disko 抹盘时清零的前 440 字节也在这里），所以只能用 MBR，
#  disko 里 MBR 只有旧式 table 类型（求值时会打印一条 legacy 警告，属预期）。
#
#  前 68MiB 留空：厂商 bootloader、env 与 Android 的保留分区表都在这一段，
#  与 ophub 的 openwrt-install-amlogic 对 s905x3 的布局一致（BLANK1=68）。
#    p1  68MiB–580MiB  FAT32  /boot  厂商 u-boot 读 emmc_autoscript、u-boot.emmc；主线 u-boot 读 extlinux
#    p2  580MiB–末尾   ext4   /
#
#  设备用 by-path：eMMC 固定挂在 sd_emmc_c（mmc@ffe07000）上，插不插 SD 卡都不会变号
#
#############################################################
{
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices.disk.emmc = {
    type = "disk";
    device = "/dev/disk/by-path/platform-ffe07000.mmc";
    content = {
      type = "table";
      format = "msdos";
      partitions = [
        {
          name = "boot";
          start = "68MiB";
          end = "580MiB";
          fs-type = "fat32";
          bootable = true;
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        }
        {
          name = "root";
          start = "580MiB";
          end = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        }
      ];
    };
  };
}
