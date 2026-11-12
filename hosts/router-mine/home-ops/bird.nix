# home-ops 的 BGP：路由器与 3 个 K8s 节点建立 eBGP，学到 Cilium 宣告的 LB /32 路由（Allow-K8s-LB-Asymmetric 因此而来）。
# nuci 只写文件，不校验、不重载；push 之后的 `bird -p` 校验与 `birdc configure` 软重载由 just router::push 负责
{ lib, ... }:
let
  net = import ../../../vars/networking.nix { inherit lib; };
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
                import all;
                export all;
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
