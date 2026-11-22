{ config, lib, ... }:
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
    # debian 变体：自带 journalctl，SSH 日志从宿主机 journald 读（alpine 变体没有）
    image = "ghcr.io/crowdsecurity/crowdsec:v1.8.2-debian@sha256:a5642c72127ee93aaac830e9f66891573fa7851b2c721987d9fef13d7d05fdfe";
    autoStart = true;
    environment = {
      TZ = "Asia/Shanghai";
      DISABLE_LOCAL_API = "true";
      AGENT_USERNAME = "vps-cc";
      CROWDSEC_BYPASS_DB_VOLUME_CHECK = "true";
      COLLECTIONS = lib.concatStringsSep "\n" [
        "crowdsecurity/linux"
        "crowdsecurity/caddy"
        "crowdsecurity/http-cve"
        "crowdsecurity/appsec-virtual-patching"
        "crowdsecurity/appsec-generic-rules"
      ];
    };
    environmentFiles = [ config.sops.templates."crowdsec-agent.env".path ];
    volumes = [
      "${./acquis-all.yaml}:/etc/crowdsec/acquis.d/all.yaml:ro"
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
