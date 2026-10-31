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

  # 服务商的路由器会发路由通告，内核据此在网卡上再生成自动地址，并排在静态地址之前。
  # 监听通配地址的 UDP 服务（hysteria2、derp 的 STUN）回包时，内核选自动地址当源地址，
  # 客户端请求的是固定地址，收到别的源地址的回包就丢弃。关掉通告与自动配置，只留静态地址
  boot.kernel.sysctl = {
    "net.ipv6.conf.${net.interface}.accept_ra" = 0;
    "net.ipv6.conf.${net.interface}.autoconf" = 0;
  };
}
