{ pkgs, ... }:
#############################################################
#
#  试机镜像：写进 U 盘或 SD 卡，插上就从它启动，eMMC 原样不动
#
#    nix build .#nixosConfigurations.hk1box.config.system.build.images.hk1box-usb
#    # 或在 Linux 上：nixos-rebuild build-image --image-variant hk1box-usb --flake .#hk1box
#
#  注册成 nixpkgs 的镜像变体（nixos/modules/image/images.nix）：image.modules 里每个条目
#  都会经 extendModules 与本机全部模块重新求值一遍，得到一份独立的系统配置，产物放在
#  system.build.images.<名字>；变体的配置可经 .passthru.config 查看。
#  不用现成的 sd-card 变体：它导入的 sd-image-aarch64.nix 是给树莓派的（固件、ttyAMA0），
#  这里只取底层的 sd-image.nix，自己填两个钩子。
#
#  与正式系统是同一份配置，只换掉存储与引导文件的位置：
#    p1 FIRMWARE（FAT）  aml_autoscript、s905_autoscript、u-boot.ext  ← 厂商 u-boot 读
#    p2 NIXOS_SD（ext4，bootable）  /boot/extlinux                     ← 主线 u-boot 读
#  主线 u-boot 的 boot_targets 以 usb0、mmc0 打头，所以 U 盘 / SD 卡优先于 eMMC。
#
#  镜像里不带 age 私钥，所以不跑 sing-box：试机阶段只验证网口、设备树、重启，
#  并作为 nixos-anywhere 装 eMMC 的目标机（不需要 kexec）。
#  客户端网关仍指着这台时，流量照常转发给主路由，只是不走代理。
#
#############################################################
let
  bootfs = pkgs.callPackage ./bootfs.nix { };
in
{
  image.modules.hk1box-usb =
    {
      config,
      lib,
      modulesPath,
      ...
    }:
    {
      imports = [ "${modulesPath}/installer/sd-card/sd-image.nix" ];

      # 分区改由 sd-image 声明，disko 的 eMMC 布局只在装机时用；两边都声明 fileSystems."/" 会冲突
      disko.enableConfig = false;
      # sd-image 以普通优先级打开它，会带进整套 linux-firmware 与一堆无关 initrd 驱动；
      # 同优先级写 false 会冲突，所以用 mkForce。这台用到的驱动在 ./hardware.nix 里列全了
      hardware.enableAllHardware = lib.mkForce false;

      image.baseName = "hk1box-usb";
      sdImage = {
        populateFirmwareCommands = ''
          cp ${bootfs}/aml_autoscript ${bootfs}/s905_autoscript ${bootfs}/u-boot.ext firmware/
        '';
        # 这里的 config 是变体自己的：extlinux 指向 U 盘版系统，不是 eMMC 版
        populateRootCommands = ''
          mkdir -p ./files/boot
          ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
        '';
      };

      # 没有 age 私钥，订阅 URL 解不开：关掉代理与拉取，只当普通转发
      services.sing-box.enable = lib.mkForce false;
      systemd.services.sing-box-sub-update.enable = lib.mkForce false;
      systemd.timers.sing-box-sub-update.enable = lib.mkForce false;
      sops.secrets = lib.mkForce { };
    };
}
