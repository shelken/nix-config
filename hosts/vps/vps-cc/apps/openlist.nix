{ config, myvars, ... }:
let
  address = myvars.networking.hostAddress."vps-cc-ts".address;
  dataDir = "/data/docker/openlist/data";
in
{
  # 业务数据目录：镜像以 UID 1001 运行，属主必须是它
  # 设成 root 会让容器建不了临时文件，openlist 在 `init logrus...` 之后静默退出 1
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 1001 1001 -"
  ];

  sops.secrets = {
    "openlist/admin-username" = { };
    "openlist/admin-password" = { };
  };

  sops.templates."openlist.env" = {
    content = ''
      ADMIN_USERNAME=${config.sops.placeholder."openlist/admin-username"}
      ADMIN_PASSWORD=${config.sops.placeholder."openlist/admin-password"}
    '';
    restartUnits = [ "docker-openlist.service" ];
  };

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
      HTTP_PORT = "80";
    };
    environmentFiles = [ config.sops.templates."openlist.env".path ];
    networks = [ "homelab" ];
    ports = [ "${address}:5244:80/tcp" ];
    volumes = [ "${dataDir}:/opt/openlist/data" ];
    extraOptions = [
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
      "homepage.href" = "http://${address}:5244";
      "homepage.description" = "专门给 kopia 使用的，连接 139 网盘";
    };
  };
}
