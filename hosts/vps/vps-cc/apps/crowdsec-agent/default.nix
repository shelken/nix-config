{ config, lib, ... }:
#############################################################
#
#  crowdsec-agent：只做检测与 AppSec 服务，LAPI 在别处（DISABLE_LOCAL_API）
#
#  继续用镜像：nixpkgs 的 services.crowdsec 能表达 agent-only + 远程 LAPI
#  （api.server.enable = false 加 api.client.credentials_path），但有两处补垫：
#  非 hub 的本地 AppSec 规则（jellyfin 豁免）module 没有落文件的 option，
#  远程 LAPI 的凭证文件也要自己渲染。这次迁移求行为等同，用容器保留原分发方式。
#  Caddy 的 AppSec 后端就是它：http://crowdsec-agent:7422
#
#############################################################
{
  sops.secrets = {
    "crowdsec/lapi-url" = { };
    "crowdsec/agent-password" = { };
  };

  sops.templates."crowdsec-agent.env" = {
    content = ''
      LOCAL_API_URL=${config.sops.placeholder."crowdsec/lapi-url"}
      AGENT_PASSWORD=${config.sops.placeholder."crowdsec/agent-password"}
    '';
    restartUnits = [ "docker-crowdsec-agent.service" ];
  };

  virtualisation.oci-containers.containers.crowdsec-agent = {
    image = "ghcr.io/crowdsecurity/crowdsec:v1.8.1@sha256:0f2523fa61ef507f15d953045cface490cc880670c62f2755ced17524107f71a";
    autoStart = true;
    environment = {
      TZ = "Asia/Shanghai";
      DISABLE_LOCAL_API = "true";
      AGENT_USERNAME = "vps-cc";
      # 容器不带 /var/lib/crowdsec 卷：状态随容器重建重置，与旧 Compose 一致
      CROWDSEC_BYPASS_DB_VOLUME_CHECK = "true";
      COLLECTIONS = lib.concatStringsSep "\n" [
        "crowdsecurity/linux"
        "crowdsecurity/caddy"
        "crowdsecurity/http-cve"
        "crowdsecurity/appsec-virtual-patching"
        "crowdsecurity/appsec-generic-rules"
        "crowdsecurity/appsec-crs"
      ];
    };
    environmentFiles = [ config.sops.templates."crowdsec-agent.env".path ];
    volumes = [
      "${./acquis-all.yaml}:/etc/crowdsec/acquis.d/all.yaml:ro"
      "${./jellyfin-exclusions.yaml}:/etc/crowdsec/appsec-configs/jellyfin-exclusions.yaml:ro"
      "/var/log:/var/log:ro"
    ];
    networks = [ "homelab" ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "crowdsec";
      "homepage.icon" = "crowdsec.svg";
      "homepage.description" = "安全检测";
    };
  };
}
