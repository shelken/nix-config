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
        size = cfg.rootSize;
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
        size = cfg.rootSize;
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
        rootSize = lib.mkOption {
          type = lib.types.str;
          default = "100%";
          example = "80G";
          description = "根分区大小；不占满时，剩余空间留给主机自己声明的分区";
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
