{
  config,
  lib,
  pkgs,
  ...
}:
#############################################################
#
#  HK1 Box（Amlogic S905X3 / meson-sm1）硬件：内核、设备树、引导
#
#  内核：nixpkgs 默认内核（主线），meson-sm1 的 eMMC、USB、千兆网口驱动都在主线里
#  设备树：主线没有 HK1，用 unifreq 维护的 dts（./dts，来源见 README），
#          它只依赖主线已有的 meson-sm1-ac2xx.dtsi，所以拿 nixpkgs 内核同版本的源码树直接编
#  引导：厂商 u-boot → autoscript → 主线 u-boot → extlinux，见 ./bootfs.nix
#
#############################################################
let
  inherit (config.boot.kernelPackages) kernel;
  bootfs = pkgs.callPackage ./bootfs.nix { };

  dtbName = "amlogic/meson-sm1-hk1box-vontar-x3.dtb";

  # 只从内核源码包里解出编 dts 要用的几个目录，不编整个内核
  dtbs = pkgs.runCommandCC "hk1box-dtbs-${kernel.version}" { nativeBuildInputs = [ pkgs.dtc ]; } ''
    tar -xf ${kernel.src} --strip-components=1 --wildcards \
      '*/arch/arm64/boot/dts/amlogic/*' \
      '*/include/dt-bindings/*' \
      '*/include/uapi/linux/input-event-codes.h' \
      '*/scripts/dtc/include-prefixes/*'
    cp ${./dts/meson-sm1-hk1box-vontar-x3.dts} arch/arm64/boot/dts/amlogic/meson-sm1-hk1box-vontar-x3.dts
    mkdir -p $out/amlogic
    $CC -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
      -I scripts/dtc/include-prefixes \
      arch/arm64/boot/dts/amlogic/meson-sm1-hk1box-vontar-x3.dts \
      | dtc -I dts -O dtb -@ -o $out/${dtbName}
  '';
in
{
  hardware.deviceTree = {
    enable = true;
    dtbSource = dtbs;
    # 写成 extlinux 的 FDT 行：主线 u-boot 的 fdtfile 是 X96 Max+ 的，必须显式指定
    name = dtbName;
  };

  boot.kernelParams = [
    "console=tty0"
    # 板载串口（主板上的 TTL 三针），排障时用
    "console=ttyAML0,115200n8"
  ];

  # 根分区在 eMMC（装好后）或 U 盘（试机镜像）上，initrd 要带上对应驱动。
  # 这些在 arm64 defconfig 里大多是 =y，编进内核的会被跳过，列出来只为换内核时不漏
  boot.initrd.availableKernelModules = [
    "meson_gx_mmc"
    "dwc3"
    "dwc3_meson_g12a"
    "phy_meson_g12a_usb2"
    "phy_meson_g12a_usb3_pcie"
    "xhci_plat_hcd"
    "usb_storage"
    "uas"
  ];

  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible = {
      enable = true;
      # /boot 是 512M 的 FAT，每代约 60M（内核 + initrd + dtb）
      configurationLimit = 5;
    };
  };

  # 在 extlinux 之外，把 emmc_autoscript 与 u-boot.emmc 也放进 /boot（eMMC 第 1 分区根目录），
  # 厂商 u-boot 开机要从这里读。nixos-anywhere 安装与之后每次部署都经过这里，文件丢了会自动补回
  system.build.installBootLoader = lib.mkForce (
    pkgs.writeShellScript "install-hk1box-bootloader" ''
      set -e
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} -d /boot -c "$@"
      install -m 0644 ${bootfs}/emmc_autoscript ${bootfs}/u-boot.emmc /boot/
    ''
  );
}
