{ config, ... }:
#############################################################
#
#  derp：自建 Tailscale DERP 中继，TLS 由 Caddy 终止（Caddyfile 里 derp 段转到 8666）
#
#  继续用镜像：nixpkgs 的 services.tailscale.derper 把 nginx、证书申请和
#  derper 的启动参数一起写死在 module 里，要在 Caddy 后面用它就得覆盖 ExecStart，
#  那已经不是「原生 module 能覆盖就不要包容器」的情形了。
#  用宿主机网络：8666/tcp 与 3478/udp 是 tailscale 客户端直连的端口，
#  两个端口在 hosts/vps/common.nix 的防火墙里已放行。
#
#############################################################
{
  sops.secrets."main-domain" = { };

  sops.templates."derp.env" = {
    content = ''
      DERP_DOMAIN=derp.${config.sops.placeholder."main-domain"}
    '';
    restartUnits = [ "docker-derp.service" ];
  };

  virtualisation.oci-containers.containers.derp = {
    image = "fredliang/derper:v1.104.5@sha256:7172639d0c463bf95fb45ec11b7638a43167db7975efb7dd05c65d70062e4d74";
    autoStart = true;
    environment = {
      TZ = "Asia/Shanghai";
      DERP_ADDR = ":8666";
      DERP_STUN_PORT = "3478";
      DERP_VERIFY_CLIENTS = "false";
    };
    environmentFiles = [ config.sops.templates."derp.env".path ];
    volumes = [ "/var/run/tailscale/tailscaled.sock:/var/run/tailscale/tailscaled.sock" ];
    extraOptions = [ "--network=host" ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "derp服务";
      "homepage.icon" = "tailscale.svg";
      "homepage.description" = "derp服务";
    };
  };
}
