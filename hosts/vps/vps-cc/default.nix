{
  lib,
  secrets,
  ...
}:
#############################################################
#
#  vps-cc：美国 KVM VPS，原先是 Ubuntu，由 nixos-anywhere 接管
#
#  共有配置见 ../common.nix；切换步骤与回滚见 ./README.md
#  网络参数是服务商分配的，没有 DHCP，写在私有的 secrets 仓库里（求值期读取，不加密）
#  硬件：kexec 阶段用 nixos-facter 生成 ./facter.json 并提交；没有报告时用 qemu-guest 的 virtio 驱动兜底
#
#############################################################
let
  net = import (secrets + "/hosts/vps-cc/network.nix");
  facterReport = ./facter.json;
in
{
  imports = [ ../common.nix ];

  hardware.facter.reportPath = lib.mkIf (builtins.pathExists facterReport) facterReport;

  networking = {
    hostName = "vps-cc";
    useDHCP = false;
    interfaces.${net.interface} = {
      mtu = net.mtu;
      tempAddress = "disabled";
      ipv4.addresses = [
        {
          inherit (net.ipv4) address prefixLength;
        }
      ];
      ipv6.addresses = map (address: {
        inherit address;
        inherit (net.ipv6) prefixLength;
      }) net.ipv6.addresses;
    };
    defaultGateway = {
      address = net.ipv4.gateway;
      interface = net.interface;
    };
    defaultGateway6 = {
      address = net.ipv6.gateway;
      interface = net.interface;
    };
  };
}
