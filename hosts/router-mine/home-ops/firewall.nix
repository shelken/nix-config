# K8s 入口与对外服务的防火墙：LB 非对称路径免连接跟踪、对外 IPv6 端口放行。
# 放行规则的目的地址只写后缀（IPv6 EUI-64，掩码 ::ffff:ffff:ffff:ffff 只匹配后 64 位）。
# 后缀由 home-ops 各应用的 Multus 固定 MAC 推出；这些 MAC 是手动随机生成的服务配置，不是设备标识，
# 所以明文放在这里（ADR 0011）。改了应用的 MAC，要同步改这里
{ ... }:
let
  ext = {
    # home-ops: k8s/infra/common/network/external/caddy-external
    caddy-external = "::63:d3ff:fe26:b439/::ffff:ffff:ffff:ffff";
    # home-ops: k8s/apps/common/qbittorrent
    qbit = "::1a:7cff:fe8e:4fb3/::ffff:ffff:ffff:ffff";
    # home-ops: k8s/infra/common/network/external/ss-rust
    ss-rust = "::2f:3eff:fee3:c3b0/::ffff:ffff:ffff:ffff";
    # home-ops: k8s/infra/common/network/tailscale/proxy/subnet-router
    tailscale = "::2e:5fff:feae:6a65/::ffff:ffff:ffff:ffff";
  };
in
{
  uci.settings.firewall = {
    rule = [
      {
        _type = "rule";
        dest = "lan";
        dest_ip = [ ext.caddy-external ];
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
        dest_ip = [ ext.qbit ];
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
        dest_ip = [ ext.ss-rust ];
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
        dest_ip = [ ext.tailscale ];
        dest_port = "44555";
        family = "ipv6";
        name = "tailscale";
        proto = "udp";
        src = "wan";
        target = "ACCEPT";
      }
    ];
  };
}
