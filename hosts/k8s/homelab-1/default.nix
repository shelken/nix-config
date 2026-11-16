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
  # 系统与 Longhorn 数据分开：根分区写满不会拖垮 Longhorn，Longhorn 写满也不会拖垮系统
  # 两者在同一块盘上：整盘重装（nixos-anywhere 默认模式）会连数据分区一起擦掉，先把数据导出
  shelken.disko.rootSize = "80G";
  disko.devices.disk.main.content.partitions.longhorn = {
    size = "100%";
    content = {
      type = "filesystem";
      format = "ext4";
      mountpoint = "/mnt/lima-longhorn";
      # 分区缺席时照常开机，只拦住 k3s；否则进 emergency 模式，SSH 不可用
      mountOptions = [
        "nofail"
        "x-systemd.device-timeout=30s"
      ];
    };
  };
  # 数据分区没挂上就不启动 k3s，避免 Longhorn 把副本写到根分区
  systemd.services.k3s.unitConfig.RequiresMountsFor = [ "/mnt/lima-longhorn" ];

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
