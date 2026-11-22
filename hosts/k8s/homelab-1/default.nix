{
  inputs,
  self,
  modulesPath,
  ...
}:
{
  imports = [
    ../common.nix
    self.modules.nixos.sops
    self.modules.nixos.k3s-nvidia-vgpu
    self.modules.nixos.openwrt-builder
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  sops.defaultSopsFile = inputs.secrets + "/sops/secrets/hosts/homelab-1.yaml";

  networking.hostName = "homelab-1";

  shelken.disko.device = "/dev/sda";
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
