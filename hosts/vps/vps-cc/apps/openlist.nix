{ ... }:
let
  dataDir = "/data/docker/openlist/data";
in
{
  # 确保业务数据持久化目录存在且属主正确
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
  ];

  virtualisation.oci-containers.containers.openlist = {
    image = "ghcr.io/shelken/openlist:v4.2.9-patch.1@sha256:595d962fc3c3df485ffa23f0246caff26fc90082c8b3698293d41d45a5a6c04e";
    autoStart = true;
    cmd = [
      "./openlist"
      "server"
      "--no-prefix"
    ];
    environment = {
      TZ = "Asia/Shanghai";
      S3_ENABLE = "true";
      S3_PORT = "5246";
      HTTP_PORT = "80";
    };
    ports = [ "5244:80/tcp" ];
    volumes = [
      "${dataDir}:/opt/openlist/data"
    ];
    extraOptions = [
      "--network=homelab"
      "--restart=always"
      "--health-cmd=wget -q --spider http://localhost:80/api/public/settings"
      "--health-interval=10s"
      "--health-timeout=1s"
      "--health-retries=10"
      "--health-start-period=30s"
    ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "openlist";
      "homepage.icon" = "openlist.svg";
      "homepage.href" = "http://localhost:5244";
      "homepage.description" = "网盘S3服务";
    };
  };

  systemd.services.docker-openlist = {
    after = [ "docker-network-homelab.service" ];
    requires = [ "docker-network-homelab.service" ];
  };
}
