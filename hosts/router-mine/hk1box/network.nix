# IoT 网出网走 hk1box：来自 IoT 网段的包查路由表 150，默认路由指向 hk1box。
# 对应的 DHCP 选项在 dhcp.nix，防火墙规则在 firewall.nix；IoT 网段本身在 home-ops/iot.nix
{ lib, ... }:
let
  net = import ../../../vars/networking.nix { inherit lib; };
in
{
  uci.settings.network = {
    iot_hk1 = {
      _type = "rule";
      "in" = "viot";
      lookup = "150";
      priority = "1000";
      src = "192.168.50.0/24";
    };

    iot_hk1_route = {
      _type = "route";
      gateway = net.hostAddress.hk1box.address;
      interface = "lan";
      table = "150";
      target = "0.0.0.0/0";
    };
  };
}
