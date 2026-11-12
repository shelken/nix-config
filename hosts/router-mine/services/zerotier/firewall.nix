# 9993 两条规则只在上游把 9993 转发进来时才有意义，并不是连接的必要条件，关闭保留
{
  uci.settings.firewall = {
    zone = [
      {
        _type = "zone";
        forward = "ACCEPT";
        input = "ACCEPT";
        masq_allow_invalid = "1";
        name = "zt";
        network = [ "zt" ];
        output = "ACCEPT";
      }
    ];

    forwarding = [
      {
        _type = "forwarding";
        dest = "zt";
        src = "lan";
      }
      {
        _type = "forwarding";
        dest = "lan";
        src = "zt";
      }
      {
        _type = "forwarding";
        dest = "iot";
        src = "zt";
      }
    ];

    rule = [
      {
        _type = "rule";
        dest_port = "9993";
        enabled = "0";
        name = "open-port";
        src = "wan";
        target = "ACCEPT";
      }
      {
        _type = "rule";
        dest = "lan";
        dest_port = "9993";
        enabled = "0";
        name = "内网穿透";
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
        dest_ip = [ "10.42.0.0/16" ];
        enabled = "0";
        name = "Allow-K8s-Pod-Zt-to-Lan";
        src = "zt";
        target = "ACCEPT";
      }
    ];
  };
}
