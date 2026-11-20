{ inputs, ... }:
let
  net = import (inputs.secrets + "/hosts/vps-cc/network.nix");
in
{
  imports = [
    ../common.nix
    ./apps
  ];

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
