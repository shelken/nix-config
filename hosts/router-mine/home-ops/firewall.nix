# K8s 入口与对外服务的防火墙：LB 非对称路径免连接跟踪、对外 IPv6 端口放行。
# 放行规则的目的地址后缀由设备 MAC 推出，取自 1Password（router-mine 条目的 firewall 分组）
{ lib, ... }:
let
  net = import ../../../vars/networking.nix { inherit lib; };
  ext = name: "{{ op://Personal/router-mine/firewall/${name} }}";
in
{
  uci.settings.firewall = {
    nat = [
      {
        _type = "nat";
        dest = "lan";
        dest_ip = "192.168.69.0/24";
        enabled = "0";
        family = "ipv4";
        name = "SNAT-K8s-Services";
        snat_ip = net.hostAddress.router-mine.address;
        src = "lan";
        target = "SNAT";
      }
    ];

    rule = [
      {
        _type = "rule";
        dest = "lan";
        dest_ip = [ (ext "caddy-external") ];
        dest_port = "443";
        family = "ipv6";
        name = "caddy-external";
        proto = [
          "tcp"
          "udp"
        ];
        src = "wan";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        dest = "lan";
        dest_port = "443";
        enabled = "0";
        family = "ipv6";
        name = "443-test";
        proto = [
          "tcp"
          "udp"
        ];
        src = "wan";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        dest = "lan";
        dest_ip = [ (ext "qbit") ];
        dest_port = "50413";
        family = "ipv6";
        name = "qbit";
        proto = [
          "tcp"
          "udp"
        ];
        src = "wan";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        dest = "lan";
        dest_ip = [ (ext "ss-rust") ];
        dest_port = "55483";
        family = "ipv6";
        name = "ss-rust";
        proto = [
          "tcp"
          "udp"
        ];
        src = "wan";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        dest = "lan";
        dest_ip = "192.168.69.0/24";
        name = "Allow-K8s-LB-Asymmetric";
        proto = [ "all" ];
        src = "lan";
        target = "NOTRACK";
      }
      {
        _type = "rule";
        dest = "lan";
        dest_ip = [ (ext "tailscale") ];
        dest_port = "44555";
        family = "ipv6";
        name = "tailscale";
        proto = [
          "tcp"
          "udp"
        ];
        src = "wan";
        target = "ACCEPT";
      }
    ];
  };
}
