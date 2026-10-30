{ self, lib, ... }:
#############################################################
#
#  lima-test：在 Lima 的 Ubuntu 虚拟机上演练「现有 Linux → NixOS」接管
#
#  磁盘：disko（modules/features/nixos/disko.nix），vz/qemu 的 virtio 盘是 /dev/vda
#  硬件：nixos-anywhere 安装时生成 ./facter.json（nixos-facter），文件不存在时用兜底模块
#  安装：见 hosts/vm/lima-test/README.md
#
#############################################################
let
  facterReport = ./facter.json;
in
{
  imports = [
    self.modules.nixos.tui
    self.modules.nixos.disko
  ];

  shelken.disko = {
    device = "/dev/vda";
    layout = "btrfs";
    swapSize = "2G";
  };

  # 有报告就交给 facter 决定内核模块、CPU 微码、网卡等；
  # 没有报告时（首次安装前做 nix eval）给出 virtio 虚拟机能启动的最小集合
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists facterReport) facterReport;
  # vz/qemu 的磁盘与网卡都是 virtio；根分区在 virtio 盘上，initrd 必须带上驱动
  # 在 aarch64 的 NixOS 内核里，这三个驱动都是 =y，也就是直接编进了内核。所以这台机器即使不列 virtio_blk 也能启动
  # 它不会有副作用：NixOS 会跳过已经编进内核的模块。换成 x86_64，或者换一个把它们编成 =m 的内核时，这份列表才真正起作用
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
    "xhci_pci"
  ];

  # 只用 EFI 回退路径（\EFI\BOOT\BOOTAA64.EFI），不写 NVRAM：
  # 原 Ubuntu 的启动项指向已被抹掉的 shim，固件找不到就会走回退路径
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = false;
  };

  nix.settings.substituters = lib.mkBefore [
    "https://icache.int.ooooo.space/cache.nixos.org"
    "https://icache.int.ooooo.space/nix-community.cachix.org"
  ];

  networking = {
    hostName = "lima-test";
    useDHCP = lib.mkDefault true;
  };

  system.stateVersion = "26.05";
}
