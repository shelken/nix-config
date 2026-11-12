# 路由器核心网络：LAN 桥与主网 VLAN、WAN、无 IPv6 的 Wi-Fi 网段、热点中继。
# IoT 网（viot、VLAN50）在 home-ops/iot.nix，IoT 出网的策略路由在 hk1box/network.nix，zt 在 services/zerotier
{ lib, ... }:
let
  net = import ../../../vars/networking.nix { inherit lib; };
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
        ports = [
          "lan1"
          "lan2"
          "lan3"
        ];
        promisc = "1";
        type = "bridge";
      }
    ];

    # lan1~3 是 PVE / K8s 节点的口：主网不打标签，其余 VLAN 打标签。VLAN50 是 IoT 网（home-ops/iot.nix）
    bridge-vlan = [
      {
        _type = "bridge-vlan";
        device = "br-lan";
        ports = [
          "lan1:u*"
          "lan2:u*"
          "lan3:u*"
        ];
        vlan = "6";
      }
      {
        _type = "bridge-vlan";
        device = "br-lan";
        ports = [
          "lan1:t"
          "lan2:t"
          "lan3:t"
        ];
        vlan = "50";
      }
      {
        _type = "bridge-vlan";
        device = "br-lan";
        ports = [
          "lan1:t"
          "lan2:t"
          "lan3:t"
        ];
        vlan = "70";
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
      dns = [
        "119.29.29.29"
        "223.5.5.5"
        "223.6.6.6"
      ];
      ip6assign = "64";
      ip6ifaceid = "::1";
      ipaddr = net.hostAddress.router-mine.address;
      multipath = "off";
      netmask = "255.255.255.0";
      proto = "static";
    };

    # 没有 device：由绑定到它的 Wi-Fi 接口提供
    noipv6 = {
      _type = "interface";
      delegate = "0";
      ipaddr = "192.168.20.1";
      multipath = "off";
      netmask = "255.255.255.0";
      proto = "static";
    };

    vipv6 = {
      _type = "interface";
      device = "br-lan.70";
      ipaddr = "192.168.70.1";
      netmask = "255.255.255.0";
      proto = "static";
    };

    wan = {
      _type = "interface";
      delegate = "0";
      device = "wan";
      dns = [
        "2400:3200::1"
        "2400:3200:baba::1"
        "223.6.6.6"
        "119.29.29.29"
        "223.5.5.5"
      ];
      metric = "10";
      multipath = "off";
      peerdns = "0";
      proto = "dhcp";
      type = "bridge";
    };

    wan6 = {
      _type = "interface";
      delegate = "0";
      device = "wan";
      dns = [
        "2001:4860:4860::8888"
        "240c::6666"
      ];
      metric = "11";
      norelease = "1";
      peerdns = "0";
      proto = "dhcpv6";
      reqaddress = "try";
      reqprefix = "auto";
    };

    # 热点中继：让路由器临时连手机热点上网，开关在 LuCI 拨（无线配置不在声明里）
    wwan2 = {
      _type = "interface";
      delegate = "0";
      device = "phy1-sta0";
      dns = [
        "2400:3200::1"
        "2400:3200:baba::1"
        "223.6.6.6"
      ];
      metric = "1";
      multipath = "off";
      peerdns = "0";
      proto = "dhcp";
    };

    wwan2_v6 = {
      _type = "interface";
      delegate = "0";
      multipath = "off";
      norelease = "1";
      proto = "dhcpv6";
      reqaddress = "try";
      reqprefix = "auto";
    };
  };
}
