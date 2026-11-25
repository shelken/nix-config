{ myvars, ... }:
let
  net = myvars.networking;
  hk1box = net.hostAddress.hk1box.address;
  router = net.hostAddress.router-mine.address;
in
{
  uci.settings.dhcp = {
    hk1box = {
      _type = "tag";
      dhcp_option = [
        "3,${hk1box}"
        "121,192.168.6.0/24,0.0.0.0,0.0.0.0/0,${hk1box},192.168.50.0/24,${router},192.168.69.0/24,${router}"
        "6,${hk1box}"
      ];
    };
    viot.dhcp_option = [ "6,${hk1box}" ];
  };
}
