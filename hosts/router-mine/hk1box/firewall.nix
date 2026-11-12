# IoT 网段只能访问 hk1box 的 DNS 与公网：先放行 DNS，再拒绝其余私网，最后放行出网，三条的顺序不能变。
# Block-LAN-IPv6-DNS 禁止 LAN 用 IPv6 直连外部 DNS，让 DNS 回到 hk1box
{ lib, ... }:
let
  net = import ../../../vars/networking.nix { inherit lib; };
in
{
  uci.settings.firewall.rule = [
    {
      _type = "rule";
      dest = "wan";
      dest_port = "53";
      family = "ipv6";
      name = "Block-LAN-IPv6-DNS";
      proto = "tcp udp";
      src = "lan";
      target = "REJECT";
    }
    {
      _type = "rule";
      dest = "lan";
      dest_ip = [ net.hostAddress.hk1box.address ];
      dest_port = "53";
      enabled = "1";
      name = "IoT-DNS-HK1";
      src = "iot";
      target = "ACCEPT";
    }
    {
      _type = "rule";
      dest = "lan";
      dest_ip = [
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
      ];
      enabled = "1";
      name = "IoT-Block-Private-LAN";
      proto = "tcp udp icmp";
      src = "iot";
      target = "REJECT";
    }
    {
      _type = "rule";
      dest = "lan";
      enabled = "1";
      name = "IoT-Internet-HK1";
      proto = "tcp udp icmp";
      src = "iot";
      target = "ACCEPT";
    }
  ];
}
