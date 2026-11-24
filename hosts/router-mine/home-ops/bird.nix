{ myvars, ... }:
let
  net = myvars.networking;
  ip = name: net.hostAddress.${name}.address;
in
{
  uci.packages = [ "bird2c" ];

  uci.files = [
    {
      path = "/etc/bird.conf";
      content = ''
        router id ${ip "router-mine"};
        log syslog { info, warning, error };

        define LOCAL_ASN = 64513;
        define K8S_ASN = 64514;

        protocol device {
            scan time 10;
        }

        protocol direct {
            ipv4;
            interface "br-lan", "br-lan.*";
        }

        protocol kernel {
            ipv4 {
                import all;
                export all;
            };
            persist;
            learn;
        }

        template bgp k8s {
            local as LOCAL_ASN;
            hold time 90;
            keepalive time 30;

            ipv4 {
                import filter {
                    if net ~ [ 192.168.69.0/24{24,32}, 10.42.0.0/16{16,32} ] then accept;
                    reject;
                };
                export none;
                next hop self;
            };
        }

        protocol bgp sakamoto_k8s from k8s {
            neighbor ${ip "sakamoto-k8s"} as K8S_ASN;
        }
        protocol bgp homelab_1 from k8s {
            neighbor ${ip "homelab-1"} as K8S_ASN;
        }
        protocol bgp yuuko_k8s from k8s {
            neighbor ${ip "yuuko-k8s"} as K8S_ASN;
        }
      '';
    }
  ];
}
