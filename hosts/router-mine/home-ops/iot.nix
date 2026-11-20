# 端口的 VLAN50 定义在 network/network.nix：匿名段按模块顺序拼接，放在同一个列表里才与路由器上的顺序一致
{
  uci.settings.network = {
    viot = {
      _type = "interface";
      device = "br-lan.50";
      ipaddr = "192.168.50.1";
      netmask = "255.255.255.0";
      proto = "static";
    };
  };

  uci.settings.wireless = {
    wifinet4 = {
      _type = "wifi-iface";
      device = "radio0";
      encryption = "psk-mixed";
      key = "{{ sops.wifi.iot.key }}";
      mode = "ap";
      network = "viot";
      ssid = "{{ sops.wifi.iot.ssid }}";
    };
    wifinet6 = {
      _type = "wifi-iface";
      device = "radio0";
      encryption = "psk-mixed";
      key = "{{ sops.wifi.iot2.key }}";
      mode = "ap";
      network = "viot";
      ssid = "{{ sops.wifi.iot2.ssid }}";
    };
  };

  uci.settings.dhcp.viot = {
    _type = "dhcp";
    interface = "viot";
    leasetime = "12h";
    limit = "150";
    start = "100";
  };

  uci.settings.firewall = {
    zone = [
      {
        _type = "zone";
        forward = "ACCEPT";
        input = "REJECT";
        name = "iot";
        network = [ "viot" ];
        output = "ACCEPT";
      }
    ];

    forwarding = [
      {
        _type = "forwarding";
        dest = "iot";
        src = "lan";
      }
    ];

    rule = [
      {
        _type = "rule";
        dest_port = "67";
        family = "ipv4";
        name = "Allow-IoT-DHCP";
        proto = "udp";
        src = "iot";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        dest_port = "5353";
        family = "ipv4";
        name = "Allow-IoT-mDNS";
        proto = "udp";
        src = "iot";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        family = "ipv4";
        icmp_type = "echo-request";
        name = "Allow-IoT-Ping";
        proto = "icmp";
        src = "iot";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        family = "ipv6";
        icmp_type = [
          "neighbour-solicitation"
          "neighbour-advertisement"
        ];
        name = "Allow-IoT-NeighbourDiscovery";
        proto = "icmp";
        src = "iot";
        target = "ACCEPT";
      }
    ];
  };
}
