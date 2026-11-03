{ config, ... }:
#############################################################
#
#  crowdsec-firewall-bouncer：按 LAPI 的决策在宿主机 iptables 上封禁
#
#  继续用镜像并保留 `--network=host`：它要操作宿主机的 iptables
#  （INPUT / FORWARD / DOCKER-USER 链），与 Docker 的 NAT 在同一张表上。
#  换 nixpkgs 的原生 module 会改成由 NixOS 防火墙侧生成规则集，
#  行为与现在这套 iptables 规则不是一个东西，需要单独验证，不在这次迁移里做。
#
#  配置文件里的 ${...} 由镜像自身的入口脚本用环境变量替换，
#  所以机密仍然只走 environmentFiles。
#
#############################################################
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
    # 操作宿主机 iptables，必须共用宿主机网络栈；no-new-privileges 与旧 Compose 一致
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
