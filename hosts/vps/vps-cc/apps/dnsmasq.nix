{ config, ... }:
#############################################################
#
#  dnsmasq：宿主机的解析入口，只发布到 127.0.0.1:53
#
#  这里试过走 nixpkgs 的原生 module，落不下来：`services.dnsmasq.configFile`
#  是 readOnly 的，配置只能由 `settings` 生成，而这份配置里的主域名与集群网关
#  地址来自 sops，sops 只能渲染整份文件。容器保留挂载 sops 渲染文件的写法，
#  与旧 Compose 的容器内 5353 + 宿主 53 映射逐个字段对齐。
#
#############################################################
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

      # 内部域与主域都交集群 k8s-gateway；更具体的内部域规则优先
      server=/int.${config.sops.placeholder."main-domain"}/${
        config.sops.placeholder."cluster/k8s-gateway-address"
      }
      server=/${config.sops.placeholder."main-domain"}/${
        config.sops.placeholder."cluster/k8s-gateway-address"
      }

      # k8s-gateway 不可用时的顺序回落；公网上游使用 1.1.1.1 / 8.8.8.8
      server=/${config.sops.placeholder."main-domain"}/1.1.1.1
      server=/${config.sops.placeholder."main-domain"}/8.8.8.8
      server=1.1.1.1
      server=8.8.8.8
    '';
    # 渲染文件默认 root:root 0400，而容器以镜像里的 dnsmasq 用户（uid 100/gid 101）运行，
    # 非 root 读不到就起不来（旧 Compose 挂的是宿主上 644 的文件，所以没暴露这个问题）。
    # 属主对齐容器用户、权限保持 0400；镜像换用户时要跟着改
    uid = 100;
    gid = 101;
    mode = "0400";
    # 配置在容器创建时被读走，密文变了要重建容器
    restartUnits = [ "docker-dnsmasq.service" ];
  };

  virtualisation.oci-containers.containers.dnsmasq = {
    image = "dockurr/dnsmasq:2.93@sha256:b40fbaa3a9c3742d5943a4bec789dabc6c5c932b2db76a4e052c84f0b8d173a2";
    autoStart = true;
    user = "dnsmasq";
    volumes = [ "${config.sops.templates."dnsmasq.conf".path}:/etc/dnsmasq.conf:ro" ];
    # 只给宿主 loopback：本机 resolv.conf 指向 127.0.0.1，
    # 绑到 tailnet 或 0.0.0.0 等于多开一个对外解析入口
    ports = [
      "127.0.0.1:53:5353/tcp"
      "127.0.0.1:53:5353/udp"
    ];
    networks = [ "homelab" ];
    extraOptions = [
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };
}
