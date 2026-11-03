{
  config,
  extendModules,
  pkgs,
  ...
}:
#############################################################
#
#  试机镜像：写进 U 盘或 SD 卡，插上就从它启动，eMMC 原样不动
#
#    nix build .#nixosConfigurations.hk1box.config.system.build.usbImage
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

  usbSystem = extendModules {
    modules = [
      (
        {
          config,
          lib,
          modulesPath,
          ...
        }:
        {
          imports = [ "${modulesPath}/installer/sd-card/sd-image.nix" ];

          # 分区改由 sd-image 声明，disko 的 eMMC 布局只在装机时用
          disko.enableConfig = false;
          # sd-image 默认打开它，会带进整套 linux-firmware 与一堆无关 initrd 驱动；
          # 这台用到的驱动在 ./hardware.nix 里列全了
          hardware.enableAllHardware = lib.mkForce false;

          image.baseName = "hk1box-usb";
          sdImage = {
            populateFirmwareCommands = ''
              cp ${bootfs}/aml_autoscript ${bootfs}/s905_autoscript ${bootfs}/u-boot.ext firmware/
            '';
            populateRootCommands = ''
              mkdir -p ./files/boot
              ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
            '';
          };

          services.sing-box.enable = lib.mkForce false;
          sops.secrets = lib.mkForce { };
        }
      )
    ];
  };
in
{
  system.build.usbImage = usbSystem.config.system.build.sdImage;
}
