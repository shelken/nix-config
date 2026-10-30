{ lib, ... }:
#############################################################
#
#  vps-test：vps-cc 的 x86_64 BIOS 演练机，跑在 Lima 的 qemu 里
#
#  共有配置见 hosts/vps/common.nix，与真机一致；这里只换网络和 SSH 端口
#  qemu 用户态网络：客户机 192.168.5.15/24，网关 192.168.5.2，没有 IPv6
#  步骤见 hosts/vps/vps-cc/README.md 的「演练」一节
#
#############################################################
{
  imports = [ ../../vps/common.nix ];

  networking = {
    hostName = "vps-test";
    useDHCP = false;
    interfaces.eth0 = {
      # 与真机同样的 MTU，验证重启后仍然生效
      mtu = 1400;
      ipv4.addresses = [
        {
          address = "192.168.5.15";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "192.168.5.2";
      interface = "eth0";
    };
  };

  # Lima 只把 Mac 本机端口转发到客户机的 22；60223 在客户机里自测
  services.openssh.ports = lib.mkForce [
    22
    60223
  ];
}
