# 声明式分区：disko 模块 + 两种常用布局（ext4 / btrfs）× 两种引导方式（uefi / bios）
# 可选功能：要用的 NixOS 主机在 imports 里加 self.modules.nixos.disko，并设置 shelken.disko.*
#
# 分区表都是 GPT，引导分区随 shelken.disko.boot：
#   - uefi：1G ESP(/boot, vfat)，引导程序由主机自己选（如 systemd-boot）
#   - bios：1M EF02 分区，不格式化，只给 GRUB 放 core.img；GRUB 直接读根分区，不单独分 /boot
# 根分区占剩余全部空间：
#   - ext4 ：一个根分区，最简单，适合测试机与小 VPS
#   - btrfs：根分区里分 @root @home @nix @log 子卷，zstd 压缩，可选 swapfile 子卷
#
# disko 生成的 fileSystems/swapDevices 会写入系统配置，所以主机的硬件配置
# （nixos-facter 报告或 nixos-generate-config --no-filesystems）里不要再写 fileSystems。
{ inputs, ... }:
{
  flake.modules.nixos.disko =
    { config, lib, ... }:
    let
      cfg = config.shelken.disko;

      esp = {
        type = "EF00";
        size = cfg.espSize;
        content = {
          type = "filesystem";
          format = "vfat";
          mountpoint = "/boot";
          mountOptions = [ "umask=0077" ];
        };
      };

      # GPT + BIOS：GRUB 的 core.img 没有 MBR 间隙可放，必须有一个不带文件系统的 EF02 分区
      biosBoot = {
        type = "EF02";
        size = "1M";
      };

      ext4Root = {
        size = "100%";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/";
        };
      };

      btrfsOpts = [
        "compress=zstd"
        "noatime"
      ];
      btrfsRoot = {
        size = "100%";
        content = {
          type = "btrfs";
          extraArgs = [ "-f" ];
          subvolumes = {
            "@root" = {
              mountpoint = "/";
              mountOptions = btrfsOpts;
            };
            "@home" = {
              mountpoint = "/home";
              mountOptions = btrfsOpts;
            };
            "@nix" = {
              mountpoint = "/nix";
              mountOptions = btrfsOpts;
            };
            "@log" = {
              mountpoint = "/var/log";
              mountOptions = btrfsOpts;
            };
          }
          // lib.optionalAttrs (cfg.swapSize != null) {
            "@swap" = {
              mountpoint = "/.swapvol";
              swap.swapfile.size = cfg.swapSize;
            };
          };
        };
      };
    in
    {
      imports = [ inputs.disko.nixosModules.disko ];

      options.shelken.disko = {
        device = lib.mkOption {
          type = lib.types.str;
          example = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_XXXX";
          description = ''
            要被清空并重新分区的整块磁盘。真机优先用 /dev/disk/by-id/...（不会因插拔顺序变化），
            虚拟机里 virtio 盘一般是 /dev/vda，SATA/SCSI 盘是 /dev/sda。
          '';
        };
        layout = lib.mkOption {
          type = lib.types.enum [
            "ext4"
            "btrfs"
          ];
          default = "ext4";
          description = "根分区布局";
        };
        boot = lib.mkOption {
          type = lib.types.enum [
            "uefi"
            "bios"
          ];
          default = "uefi";
          description = ''
            固件引导方式。目标机里 `ls /sys/firmware/efi` 存在就是 uefi，不存在就是 bios。
            bios 会建 EF02 分区并启用 GRUB（安装到 device）；uefi 的引导程序由主机自己配置。
          '';
        };
        espSize = lib.mkOption {
          type = lib.types.str;
          default = "1G";
          description = "仅 uefi：EFI 系统分区大小（/boot）；systemd-boot 每个代数都放一份内核，留宽一点";
        };
        swapSize = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "8G";
          description = "仅 btrfs 布局：swapfile 大小，null 表示不建 swap";
        };
      };

      config = {
        assertions = [
          {
            assertion = cfg.swapSize == null || cfg.layout == "btrfs";
            message = "shelken.disko.swapSize 只在 layout = \"btrfs\" 时生效";
          }
        ];

        # bios：启用 GRUB；安装位置由 disko 根据 EF02 分区所在的磁盘自动加入 boot.loader.grub.devices
        boot.loader.grub.enable = lib.mkIf (cfg.boot == "bios") true;

        disko.devices.disk.main = {
          type = "disk";
          inherit (cfg) device;
          content = {
            type = "gpt";
            partitions = {
              root = if cfg.layout == "btrfs" then btrfsRoot else ext4Root;
            }
            // (if cfg.boot == "bios" then { boot = biosBoot; } else { ESP = esp; });
          };
        };
      };
    };
}
