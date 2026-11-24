{ myvars, ... }:
let
  net = myvars.networking;
  hw = import ../hardware.nix;
in
{
  uci.settings.network = {
    globals = {
      _type = "globals";
      packet_steering = "1";
      ula_prefix = "fd00:6666:6666::/64";
    };

    device = [
      {
        _type = "device";
        name = "br-lan";
        ports = hw.lanPorts;
        type = "bridge";
      }
    ];

    bridge-vlan = [
      {
        _type = "bridge-vlan";
        device = "br-lan";
        ports = map (p: "${p}:u*") hw.lanPorts;
        vlan = "6";
      }
      {
        _type = "bridge-vlan";
        device = "br-lan";
        ports = map (p: "${p}:t") hw.lanPorts;
        vlan = "50";
      }
    ];

    loopback = {
      _type = "interface";
      device = "lo";
      ipaddr = "127.0.0.1";
      netmask = "255.0.0.0";
      proto = "static";
    };

    lan = {
      _type = "interface";
      delegate = "0";
      device = "br-lan.6";
      ip6assign = "64";
      ip6ifaceid = "::1";
      ipaddr = net.hostAddress.router-mine.address;
      netmask = "255.255.255.0";
      proto = "static";
    };

    # 没有 device：由绑定到它的 Wi-Fi 接口提供
    noipv6 = {
      _type = "interface";
      delegate = "0";
      ipaddr = "192.168.20.1";
      netmask = "255.255.255.0";
      proto = "static";
    };

    wan = {
      _type = "interface";
      delegate = "0";
      device = hw.wanDevice;
      dns = [
        "223.5.5.5"
        "223.6.6.6"
        "119.29.29.29"
        "2400:3200::1"
      ];
      metric = "10";
      peerdns = "0";
      proto = "dhcp";
    };

    wan6 = {
      _type = "interface";
      delegate = "0";
      device = hw.wanDevice;
      metric = "11";
      norelease = "1";
      peerdns = "0";
      proto = "dhcpv6";
      reqaddress = "try";
      reqprefix = "auto";
    };

    hotspot = {
      _type = "interface";
      delegate = "0";
      device = hw.hotspotDevice;
      dns = [
        "2400:3200::1"
        "2400:3200:baba::1"
        "223.6.6.6"
      ];
      metric = "1";
      peerdns = "0";
      proto = "dhcp";
    };

    hotspot_v6 = {
      _type = "interface";
      delegate = "0";
      norelease = "1";
      proto = "dhcpv6";
      reqaddress = "try";
      reqprefix = "auto";
    };
  };
}
