{ self, modulesPath, ... }:
#############################################################
#
#  homelab-1：PVE 虚拟机里的 k3s GPU worker（vGPU + Intel 核显直通）
#
#  共有配置见 ../common.nix；切换与重装流程见 ../README.md；GPU 取舍见 k3s-nvidia-vgpu 功能的 README
#
#############################################################
{
  imports = [
    ../common.nix
    self.modules.nixos.k3s-nvidia-vgpu
    # PVE 是标准 qemu 虚拟机：virtio 驱动进 initrd
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  networking.hostName = "homelab-1";

  shelken.disko.device = "/dev/sda";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  services.qemuGuest.enable = true;

  # Intel 核显直通：给 intel-device-plugin 与媒体转码
  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;

  shelken.k3s = {
    role = "agent";
    nodeLabels = [
      "intel.feature.node.kubernetes.io/gpu=true"
      "nvidia.com/gpu.present=true"
      "node.longhorn.io/create-default-disk=true"
    ];
  };
}
