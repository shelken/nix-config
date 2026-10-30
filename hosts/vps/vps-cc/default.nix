{ secrets, ... }:
#############################################################
#
#  vps-cc：美国 KVM VPS，原先是 Ubuntu，由 nixos-anywhere 接管
#
#  共有配置见 ../common.nix；切换步骤与回滚见 ./README.md
#  网络参数是服务商分配的，没有 DHCP，写在私有的 secrets 仓库里（求值期读取，不加密）
#  硬件用 qemu-guest 的 virtio 驱动；nixos-facter 报告含序列号与 MAC，不提交进公开仓库，只在 kexec 阶段拿来核对
#
#############################################################
let
  net = import (secrets + "/hosts/vps-cc/network.nix");
in
{
  imports = [ ../common.nix ];

  networking = {
    hostName = "vps-cc";
    useDHCP = false;
    interfaces.${net.interface} = {
      inherit (net) mtu;
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
