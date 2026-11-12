# 客户端的默认网关与 DNS 指向 hk1box；121 号选项下发 IoT 网段的例外路由，
# 让访问 IoT 的流量走主路由，不经旁路由 masq 改写源地址
{ lib, ... }:
let
  net = import ../../../vars/networking.nix { inherit lib; };
  hk1box = net.hostAddress.hk1box.address;
in
{
  uci.settings.dhcp = {
    lan.dhcp_option = [
      "3,${hk1box}"
      "121,0.0.0.0/0,${hk1box},192.168.50.0/24,${net.hostAddress.router-mine.address}"
      "6,${hk1box}"
    ];
    viot.dhcp_option = [ "6,${hk1box}" ];
  };
}
