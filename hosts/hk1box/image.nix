{ pkgs, ... }:
#  不用现成的 sd-card 变体：它导入的 sd-image-aarch64.nix 是给树莓派的（固件、ttyAMA0），
#  这里只取底层的 sd-image.nix，自己填两个钩子。
let
  bootfs = pkgs.callPackage ./bootfs.nix { };
in
{
  image.modules.hk1box-usb =
    {
      config,
      lib,
      myvars,
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
        populateRootCommands = ''
          mkdir -p ./files/boot
          ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
        '';
      };

      services.sing-box.enable = lib.mkForce false;
      sops.secrets = lib.mkForce { };
      users.users.${myvars.username}.hashedPasswordFile = lib.mkForce null;
      users.users.root.hashedPasswordFile = lib.mkForce null;

      system.disableInstallerTools = lib.mkForce false;
    };
}
