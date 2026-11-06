{ config, ... }:
#############################################################
#
#  sbtools-server：配置交付服务，Caddy 反代 subs.<域名> 到它的 8080
#
#  自建镜像 + 一个私钥环境变量，继续用镜像。不发布端口：
#  只有 homelab 网络里的 Caddy 按容器名访问。
#
#############################################################
{
  sops.secrets."sbtools/server-private-key" = { };

  sops.templates."sbtools-server.env" = {
    content = ''
      SERVER_PRIVATE_KEY=${config.sops.placeholder."sbtools/server-private-key"}
    '';
    restartUnits = [ "docker-sbtools-server.service" ];
  };

  virtualisation.oci-containers.containers.sbtools-server = {
    image = "ghcr.io/shelken/proxy/sbtools-server:v0.8.0@sha256:697f7c4f7e83a52e8465cc28886a031e7b0ace83e8d8f4ab5a17a82a2823f4b3";
    autoStart = true;
    environment = {
      TZ = "Asia/Shanghai";
      PORT = "8080";
    };
    environmentFiles = [ config.sops.templates."sbtools-server.env".path ];
    networks = [ "homelab" ];
    extraOptions = [
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "sbtools";
      "homepage.icon" = "docker-moby.svg";
      "homepage.description" = "singbox配置生成服务";
    };
  };
}
