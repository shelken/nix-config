{ config, ... }:
let
  dbDir = "/data/docker/fluent-bit/db";
in
#############################################################
#
#  fluent-bit：把 Caddy 的访问日志转到集群里的 VictoriaLogs
#
#  继续用镜像：它要 tail 宿主机的 /var/log/caddy 并把 db 落在宿主机目录，
#  nixpkgs 的 fluent-bit module 是 DynamicUser + 单位硬化，没有 StateDirectory、
#  ReadOnlyPaths、EnvironmentFile 这些开关，换过去得整段覆盖它的 unit。
#  docker.sock 是旧 Compose 就挂着的（当前配置并未用它），这里按原样保留。
#
#############################################################
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
    # 固定版本：与集群 chart 的 appVersion 对齐
    image = "ghcr.io/fluent/fluent-bit:5.2.0@sha256:a48190bf67679495a332fd61025421a46e7e4d168380185a8e16da2e9acc3126";
    autoStart = true;
    cmd = [
      "-c"
      "/fluent-bit/etc/fluent-bit.yaml"
    ];
    environment = {
      TZ = "Asia/Shanghai";
      VICTORIA_LOGS_PORT = "9428";
      # fluent-bit.yaml 里用它给每行日志打标签
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
