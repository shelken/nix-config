{ config, pkgs, ... }:
let
  logDir = "/data/docker/kopia/logs";
in
{
  # 确保 kopia 日志持久化目录存在
  systemd.tmpfiles.rules = [
    "d ${logDir} 0755 root root -"
  ];

  virtualisation.oci-containers.containers.kopia = {
    image = "kopia/kopia:0.23.1";
    autoStart = true;
    environment = {
      TZ = "Asia/Shanghai";
      KOPIA_CONFIG_PATH = "/config/repository.config";
      KOPIA_CACHE_DIRECTORY = "/config/cache";
      KOPIA_LOG_DIR = "/config/logs";
      KOPIA_MIN_SEVERITY = "warning";
    };
    ports = [ "51515:51515/tcp" ];
    volumes = [
      "kopia_cache:/config/cache"
      "${logDir}:/config/logs"
      "/data:/backup/data:ro"
    ];
    extraOptions = [
      "--network=homelab"
      "--hostname=vps"
      "--restart=always"
    ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "kopia";
      "homepage.icon" = "kopia.svg";
      "homepage.href" = "http://localhost:51515/tasks";
      "homepage.description" = "备份服务";
    };
  };

  # 启动前等待 OpenList 的 Docker 健康检查达到 healthy 状态
  systemd.services.docker-kopia = {
    after = [
      "docker-network-homelab.service"
      "docker-openlist.service"
    ];
    requires = [
      "docker-network-homelab.service"
      "docker-openlist.service"
    ];
    serviceConfig = {
      ExecStartPre = [
        (pkgs.writeShellScript "wait-for-openlist" ''
          echo "Waiting for openlist container to become healthy..."
          for i in $(${pkgs.coreutils}/bin/seq 1 30); do
            status="$(${pkgs.docker}/bin/docker inspect --format='{{json .State.Health.Status}}' openlist 2>/dev/null || echo '"unknown"')"
            if [ "$status" = '"healthy"' ]; then
              echo "openlist is healthy!"
              exit 0
            fi
            echo "openlist health status: $status (attempt $i/30), waiting 2s..."
            ${pkgs.coreutils}/bin/sleep 2
          done
          echo "Timeout waiting for openlist to become healthy!" >&2
          exit 1
        '')
      ];
    };
  };
}
