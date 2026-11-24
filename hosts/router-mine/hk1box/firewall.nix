{ myvars, ... }:
let
  net = myvars.networking;
in
{
  uci.settings.firewall.rule = [
    {
      _type = "rule";
      dest = "wan";
      dest_port = "53 853";
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
