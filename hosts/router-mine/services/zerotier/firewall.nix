# Allow-K8s-Pod-Zt-to-Lan 含 Pod 网段，匿名段无法拆开，整条在私有部分
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
    ];
  };
}
