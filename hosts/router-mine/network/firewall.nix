# 通用部分：默认策略、lan/wan/iot 区域、OpenWrt 标准的 wan 入站放行。
# zt 区域在 services/zerotier，对外 IPv6 放行与 K8s 相关在 home-ops，经 hk1box 的 IoT 规则在 hk1box
{
  uci.settings.firewall = {
    defaults = [
      {
        _type = "defaults";
        auto_includes = "1";
        drop_invalid = "1";
        flow_offloading = "1";
        flow_offloading_hw = "1";
        forward = "REJECT";
        fullcone = "1";
        input = "REJECT";
        output = "ACCEPT";
        synflood_protect = "1";
      }
    ];

    zone = [
      {
        _type = "zone";
        forward = "ACCEPT";
        input = "ACCEPT";
        name = "lan";
        network = [
          "lan"
          "vipv6"
          "noipv6"
        ];
        output = "ACCEPT";
      }
      {
        _type = "zone";
        forward = "REJECT";
        input = "REJECT";
        masq = "1";
        mtu_fix = "1";
        name = "wan";
        network = [
          "wan"
          "wan6"
          "wwan"
          "wwan2"
          "wwan2_v6"
        ];
        output = "ACCEPT";
      }
      {
        _type = "zone";
        forward = "ACCEPT";
        input = "ACCEPT";
        name = "iot";
        network = [ "viot" ];
        output = "ACCEPT";
      }
    ];

    forwarding = [
      {
        _type = "forwarding";
        dest = "wan";
        src = "lan";
      }
      {
        _type = "forwarding";
        dest = "iot";
        src = "lan";
      }
      {
        _type = "forwarding";
        dest = "wan";
        src = "iot";
      }
    ];

    nat = [
      {
        _type = "nat";
        device = "wan";
        enabled = "0";
        family = "ipv6";
        name = "v6Nat";
        proto = [ "all" ];
        src = "*";
        target = "MASQUERADE";
      }
    ];

    rule = [
      {
        _type = "rule";
        dest_port = "68";
        family = "ipv4";
        name = "Allow-DHCP-Renew";
        proto = "udp";
        src = "wan";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        family = "ipv4";
        icmp_type = "echo-request";
        name = "Allow-Ping";
        proto = "icmp";
        src = "wan";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        family = "ipv4";
        name = "Allow-IGMP";
        proto = "igmp";
        src = "wan";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        dest_port = "546";
        family = "ipv6";
        name = "Allow-DHCPv6";
        proto = "udp";
        src = "wan";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        family = "ipv6";
        icmp_type = [
          "130/0"
          "131/0"
          "132/0"
          "143/0"
        ];
        name = "Allow-MLD";
        proto = "icmp";
        src = "wan";
        src_ip = "fe80::/10";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        family = "ipv6";
        icmp_type = [
          "echo-request"
          "echo-reply"
          "destination-unreachable"
          "packet-too-big"
          "time-exceeded"
          "bad-header"
          "unknown-header-type"
          "router-solicitation"
          "neighbour-solicitation"
          "router-advertisement"
          "neighbour-advertisement"
        ];
        limit = "1000/sec";
        name = "Allow-ICMPv6-Input";
        proto = "icmp";
        src = "wan";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        dest = "*";
        family = "ipv6";
        icmp_type = [
          "echo-request"
          "echo-reply"
          "destination-unreachable"
          "packet-too-big"
          "time-exceeded"
          "bad-header"
          "unknown-header-type"
        ];
        limit = "1000/sec";
        name = "Allow-ICMPv6-Forward";
        proto = "icmp";
        src = "wan";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        dest = "lan";
        name = "Allow-IPSec-ESP";
        proto = "esp";
        src = "wan";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        dest = "lan";
        dest_port = "500";
        name = "Allow-ISAKMP";
        proto = "udp";
        src = "wan";
        target = "ACCEPT";
      }
    ];
  };
}
