{ config, ... }:
let
  # Caddy 用 ACME 申请下来的证书目录；挂整个 acme 目录而不是带域名的子目录，
  # 因为挂载路径在构建期就得确定，域名只存在于 sops 模板里
  certDir = "/data/docker/caddy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory";
in
#############################################################
#
#  hysteria2：公网 UDP 代理，证书直接复用 Caddy 申请的 wildcard 证书
#
#  只有镜像、没有 nixpkgs module，继续用镜像 + 宿主机网络（10357/udp）。
#  配置整体含口令与域名，走 sops 模板渲染后再挂进容器。
#
#############################################################
{
  sops.secrets = {
    "main-domain" = { };
    "hysteria2/obfs-password" = { };
    "hysteria2/auth-password" = { };
  };

  sops.templates."hysteria2-config.yaml" = {
    content = ''
      listen: :10357

      tls:
        cert: /data/hysteria2/tls/wildcard_.${config.sops.placeholder."main-domain"}/wildcard_.${
          config.sops.placeholder."main-domain"
        }.crt
        key: /data/hysteria2/tls/wildcard_.${config.sops.placeholder."main-domain"}/wildcard_.${
          config.sops.placeholder."main-domain"
        }.key

      obfs:
        type: salamander
        salamander:
          password: ${config.sops.placeholder."hysteria2/obfs-password"}

      auth:
        type: password
        password: ${config.sops.placeholder."hysteria2/auth-password"}

      bandwidth:
        up: 160 mbps
        down: 160 mbps

      masquerade:
        type: proxy
        proxy:
          url: https://www.bing.com
          rewriteHost: true
    '';
    restartUnits = [ "docker-hysteria2.service" ];
  };

  virtualisation.oci-containers.containers.hysteria2 = {
    image = "tobyxdd/hysteria:v2.13.0@sha256:92b06917b2abb940e90ea6dc9215c1b1ceea69fa7edc1374daf3cde36e422740";
    autoStart = true;
    cmd = [
      "server"
      "-c"
      "/etc/hysteria/config.yaml"
    ];
    volumes = [
      "${config.sops.templates."hysteria2-config.yaml".path}:/etc/hysteria/config.yaml:ro"
      "${certDir}:/data/hysteria2/tls:ro"
    ];
    extraOptions = [ "--network=host" ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "hysteria2";
      "homepage.icon" =
        "https://cdn.jsdelivr.net/gh/apernet/hysteria-website@master/docs/assets/logo.svg";
      "homepage.description" = "hysteria2";
    };
  };
}
