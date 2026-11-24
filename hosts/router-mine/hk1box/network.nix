{ myvars, ... }:
let
  net = myvars.networking;
in
{
  uci.settings.network = {
    iot_local_main = {
      _type = "rule";
      "in" = "viot";
      lookup = "main";
      priority = "900";
      src = "192.168.50.0/24";
      suppress_prefixlength = "0";
    };

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
