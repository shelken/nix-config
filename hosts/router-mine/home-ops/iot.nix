# home-ops 的 IoT 网（VLAN50）：Home Assistant、go2rtc 等经 Multus 接入，节点的 eth1.50 由 lan1~3 的 VLAN 标签送达。
# 网段、DHCP 基础段、防火墙区域与入站放行都在这里；DHCP 选项与出网策略（经 hk1box）在 hk1box/。
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

  # IoT 的两个 SSID，SSID 与密码在 1Password（router-mine 条目的 wifi 分组）
  uci.settings.wireless = {
    wifinet4 = {
      _type = "wifi-iface";
      device = "radio0";
      encryption = "psk-mixed";
      key = "{{ op://Personal/router-mine/wifi/iot-key }}";
      mode = "ap";
      network = "viot";
      ssid = "{{ op://Personal/router-mine/wifi/iot-ssid }}";
    };
    wifinet6 = {
      _type = "wifi-iface";
      device = "radio0";
      encryption = "psk-mixed";
      key = "{{ op://Personal/router-mine/wifi/iot2-key }}";
      mode = "ap";
      network = "viot";
      ssid = "{{ op://Personal/router-mine/wifi/iot2-ssid }}";
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

    # IoT 网段只能向路由器本机要这几样：DHCP、mDNS（avahi 反射到主网）、ping、IPv6 邻居发现。
    # 实测 IoT 发给路由器的流量只有 mDNS，DNS 由 DHCP 指向 hk1box，其余一律拒绝；某个设备出问题再逐项开放
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
