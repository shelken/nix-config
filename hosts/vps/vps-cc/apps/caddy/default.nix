{ config, myvars, ... }:
let
  address = myvars.networking.hostAddress."vps-cc-ts".address;
  dataDir = "/data/docker/caddy";
  logDir = "/var/log/caddy";
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
    "d ${dataDir}/site 0755 root root -"
    "d ${dataDir}/data 0755 root root -"
    "d ${dataDir}/config 0755 root root -"
    "d ${logDir} 0755 root root -"
  ];

  sops.secrets = {
    "main-domain" = { };
    "envoy-external-ip" = { };
    "caddy/cloudflare-api-token" = { };
    "crowdsec/lapi-url" = { };
    "crowdsec/caddy-bouncer-api-key" = { };
  };

  sops.templates."caddy.env" = {
    content = ''
      MAIN_DOMAIN=${config.sops.placeholder."main-domain"}
      ENVOY_EXTERNAL_IP=${config.sops.placeholder."envoy-external-ip"}
      CLOUDFLARE_API_TOKEN=${config.sops.placeholder."caddy/cloudflare-api-token"}
      CROWDSEC_LOCAL_API_URL=${config.sops.placeholder."crowdsec/lapi-url"}
      CROWDSEC_CADDY_BOUNCER_API_KEY=${config.sops.placeholder."crowdsec/caddy-bouncer-api-key"}
    '';
    restartUnits = [ "docker-caddy.service" ];
  };

  virtualisation.oci-containers.containers.caddy = {
    image = "ghcr.io/shelken/caddy:2.11.9@sha256:f555065510267ad5413a5b6b8ee34b1a2abbd4804c3e74a24e6a9c15f58a4dba";
    autoStart = true;
    environment = {
      TZ = "Asia/Shanghai";
      GODEBUG = "multipathtcp=0";
    };
    environmentFiles = [ config.sops.templates."caddy.env".path ];
    volumes = [
      "${./Caddyfile}:/etc/caddy/Caddyfile:ro"
      "${dataDir}/site:/srv"
      "${dataDir}/data:/data"
      "${dataDir}/config:/config"
      "${logDir}:/var/log/caddy"
    ];
    ports = [
      "80:80/tcp"
      "443:443/tcp"
      "443:443/udp"
      "${address}:2019:2019/tcp"
    ];
    extraOptions = [
      "--ulimit=nofile=65536:65536"
      "--sysctl=net.mptcp.enabled=0"
    ];
    networks = [ "homelab" ];
    dependsOn = [ "crowdsec-agent" ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "vps-caddy";
      "homepage.icon" = "caddy.svg";
      "homepage.description" = "vps反向代理";
      "homepage.widget.type" = "caddy";
      "homepage.widget.url" = "http://ts-node-vps.network.svc:2019";
    };
  };
}
