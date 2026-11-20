{ config, ... }:
let
  dbDir = "/data/docker/fluent-bit/db";
in
{
  systemd.tmpfiles.rules = [
    "d ${dbDir} 0755 root root -"
  ];

  sops.secrets."fluent-bit/victoria-logs-host" = { };

  sops.templates."fluent-bit.env" = {
    content = ''
      VICTORIA_LOGS_HOST=${config.sops.placeholder."fluent-bit/victoria-logs-host"}
    '';
    restartUnits = [ "docker-fluent-bit.service" ];
  };

  virtualisation.oci-containers.containers.fluent-bit = {
    image = "ghcr.io/fluent/fluent-bit:5.2.0@sha256:e2718c47aaab7d99587fdffe78818549bdd09dee5e30a9199d2ff3da6e2c7628";
    autoStart = true;
    cmd = [
      "-c"
      "/fluent-bit/etc/fluent-bit.yaml"
    ];
    environment = {
      TZ = "Asia/Shanghai";
      VICTORIA_LOGS_PORT = "9428";
      HOSTNAME = "vps-cc";
    };
    environmentFiles = [ config.sops.templates."fluent-bit.env".path ];
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock:ro"
      "/var/log/caddy:/var/log/caddy:ro"
      "${dbDir}:/fluent-bit/db"
      "${./fluent-bit.yaml}:/fluent-bit/etc/fluent-bit.yaml:ro"
    ];
    networks = [ "homelab" ];
  };
}
