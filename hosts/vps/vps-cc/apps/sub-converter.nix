{ config, ... }:
#############################################################
#
#  sub-converter：订阅转换，Caddy 反代 sub.<域名> 到它的 25500
#
#  自建镜像 + 环境变量配置，继续用镜像。端口发布到宿主 loopback：
#  Caddy 走 homelab 网络直接连容器名，这个映射只给宿主机排障用。
#
#############################################################
{
  sops.secrets."main-domain" = { };

  sops.templates."sub-converter.env" = {
    content = ''
      MANAGED_PREFIX=https://sub.${config.sops.placeholder."main-domain"}
    '';
    restartUnits = [ "docker-sub-converter.service" ];
  };

  virtualisation.oci-containers.containers.sub-converter = {
    image = "ghcr.io/shelken/subconverter:1.8.1@sha256:b1e88944e8ed0baf6e47c872e445a080efa443a9432e5bc7efbb7cbb41afce70";
    autoStart = true;
    environment = {
      TZ = "Asia/Shanghai";
      API_MODE = "false";
      # 旧 Compose 的原值；API_MODE=false 时该 token 不参与鉴权
      API_TOKEN = "password";
    };
    environmentFiles = [ config.sops.templates."sub-converter.env".path ];
    ports = [ "127.0.0.1:25500:25500/tcp" ];
    networks = [ "homelab" ];
    extraOptions = [
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "订阅转换";
      "homepage.icon" = "docker-moby.svg";
      "homepage.description" = "订阅转换";
    };
  };
}
