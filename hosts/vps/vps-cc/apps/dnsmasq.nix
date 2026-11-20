{ config, myvars, ... }:
let
  address = myvars.networking.hostAddress."vps-cc-ts".address;
in
#  这里试过走 nixpkgs 的原生 module，落不下来：`services.dnsmasq.configFile`
#  是 readOnly 的，配置只能由 `settings` 生成，而这份配置里的主域名与集群网关
#  地址来自 sops，sops 只能渲染整份文件。容器保留挂载 sops 渲染文件的写法，
{
  sops.secrets = {
    "main-domain" = { };
    "cluster/k8s-gateway-address" = { };
  };

  sops.templates."dnsmasq.conf" = {
    content = ''
      port=5353
      listen-address=0.0.0.0
      bind-interfaces
      no-resolv
      strict-order

      server=/int.${config.sops.placeholder."main-domain"}/${
        config.sops.placeholder."cluster/k8s-gateway-address"
      }
      server=/${config.sops.placeholder."main-domain"}/${
        config.sops.placeholder."cluster/k8s-gateway-address"
      }

      server=/${config.sops.placeholder."main-domain"}/1.1.1.1
      server=/${config.sops.placeholder."main-domain"}/8.8.8.8
      server=1.1.1.1
      server=8.8.8.8
    '';
    # 渲染文件默认 root:root 0400，而容器以镜像里的 dnsmasq 用户（uid 100/gid 101）运行，
    # 非 root 读不到就起不来（旧 Compose 挂的是宿主上 644 的文件，所以没暴露这个问题）。
    uid = 100;
    gid = 101;
    mode = "0400";
    restartUnits = [ "docker-dnsmasq.service" ];
  };

  virtualisation.oci-containers.containers.dnsmasq = {
    image = "dockurr/dnsmasq:2.93@sha256:b40fbaa3a9c3742d5943a4bec789dabc6c5c932b2db76a4e052c84f0b8d173a2";
    autoStart = true;
    user = "dnsmasq";
    volumes = [ "${config.sops.templates."dnsmasq.conf".path}:/etc/dnsmasq.conf:ro" ];
    ports = [
      "127.0.0.1:53:5353/tcp"
      "127.0.0.1:53:5353/udp"
      "${address}:5353:5353/udp"
    ];
    networks = [ "homelab" ];
    extraOptions = [
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };
}
