# 声明式分区：disko 模块 + 两种常用布局（ext4 / btrfs）
# 可选功能：要用的 NixOS 主机在 imports 里加 self.modules.nixos.disko，并设置 shelken.disko.*
#
# 布局都是 GPT + 1G ESP(/boot, vfat) + 根分区：
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
        espSize = lib.mkOption {
          type = lib.types.str;
          default = "1G";
          description = "EFI 系统分区大小（/boot）；systemd-boot 每个代数都放一份内核，留宽一点";
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

        disko.devices.disk.main = {
          type = "disk";
          inherit (cfg) device;
          content = {
            type = "gpt";
            partitions = {
              ESP = esp;
              root = if cfg.layout == "btrfs" then btrfsRoot else ext4Root;
            };
          };
        };
      };
    };
}
