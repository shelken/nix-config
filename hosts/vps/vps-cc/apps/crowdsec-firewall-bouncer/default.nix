{ config, ... }:
#  继续用镜像并保留 `--network=host`：它要操作宿主机的 iptables
#  （INPUT / FORWARD / DOCKER-USER 链），与 Docker 的 NAT 在同一张表上。
#  配置文件里的 ${...} 由镜像自身的入口脚本用环境变量替换，
{
  sops.secrets = {
    "crowdsec/lapi-url" = { };
    "crowdsec/firewall-bouncer-api-key" = { };
  };

  sops.templates."crowdsec-firewall-bouncer.env" = {
    content = ''
      CROWDSEC_LOCAL_API_URL=${config.sops.placeholder."crowdsec/lapi-url"}
      CROWDSEC_FIREWALL_BOUNCER_API_KEY=${config.sops.placeholder."crowdsec/firewall-bouncer-api-key"}
    '';
    restartUnits = [ "docker-crowdsec-firewall-bouncer.service" ];
  };

  virtualisation.oci-containers.containers.crowdsec-firewall-bouncer = {
    image = "ghcr.io/shgew/cs-firewall-bouncer-docker:v0.0.38@sha256:ece5da4dbc65e84784e1d21043667ddee34c0fc8e74bdb95d2e378021dc97f0e";
    autoStart = true;
    environment.TZ = "Asia/Shanghai";
    environmentFiles = [ config.sops.templates."crowdsec-firewall-bouncer.env".path ];
    volumes = [
      "${./crowdsec-firewall-bouncer.yaml}:/config/crowdsec-firewall-bouncer.yaml:ro"
      "/etc/localtime:/etc/localtime:ro"
    ];
    capabilities = {
      NET_ADMIN = true;
      NET_RAW = true;
    };
    extraOptions = [
      "--network=host"
      "--security-opt=no-new-privileges:true"
    ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "firewall-bouncer";
      "homepage.icon" = "crowdsec.svg";
      "homepage.description" = "防火墙封禁";
    };
  };
}
