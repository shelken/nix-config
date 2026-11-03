{ config, ... }:
let
  address = config.shelken.vpsContainers.tailscaleAddress;
  dataDir = "/data/docker/openlist/data";
in
{
  # 业务数据目录：docker 以 root 写入，与旧系统保持一致
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
  ];

  # admin 口令：密文留在私有 secrets 仓库，激活时渲染成容器可读的环境文件
  # kopia 只经 WebDAV 取 openlist 的仓库，S3 不再由这份配置开启
  sops.secrets = {
    "openlist/admin-username" = { };
    "openlist/admin-password" = { };
  };

  sops.templates."openlist.env" = {
    content = ''
      ADMIN_USERNAME=${config.sops.placeholder."openlist/admin-username"}
      ADMIN_PASSWORD=${config.sops.placeholder."openlist/admin-password"}
    '';
    # 环境文件在容器创建时被读走，改密文后要重建容器才会生效
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

  systemd.services.docker-openlist = {
    after = [ "docker-network-homelab.service" ];
    requires = [ "docker-network-homelab.service" ];
  };
}
