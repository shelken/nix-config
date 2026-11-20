{ config, myvars, ... }:
let
  address = myvars.networking.hostAddress."vps-cc-ts".address;
  logDir = "/data/docker/kopia/logs";

  cacheVolume = "homelab-compose_kopia_cache";

  shared = ../../../../../modules/features/backup/kopia/server;
in
{
  systemd.tmpfiles.rules = [
    "d ${logDir} 0755 root root -"
  ];

  sops.secrets = {
    "kopia/password" = { };
    "kopia/webhook-url" = { };
    "openlist/webdav-username" = { };
    "openlist/webdav-password" = { };
  };

  sops.templates."kopia.env" = {
    content = ''
      KOPIA_PASSWORD=${config.sops.placeholder."kopia/password"}
      KOPIA_WEBHOOK_URL=${config.sops.placeholder."kopia/webhook-url"}
      KOPIA_WEBDAV_USERNAME=${config.sops.placeholder."openlist/webdav-username"}
      KOPIA_WEBDAV_PASSWORD=${config.sops.placeholder."openlist/webdav-password"}
    '';
    restartUnits = [ "docker-kopia.service" ];
  };

  virtualisation.oci-containers.containers.kopia = {
    image = "kopia/kopia:0.23.1@sha256:89fd95ee2942880ca00eae964266958a394421ddbdf69bca62e38afc55f5900e";
    autoStart = true;
    entrypoint = "/app/scripts/entrypoint.sh";
    # 策略与 webhook 对账按 `shelken@<主机名>` 找目标，必须保持 vps
    hostname = "vps";
    environment = {
      TZ = "Asia/Shanghai";
      KOPIA_CONFIG_PATH = "/config/repository.config";
      KOPIA_CACHE_DIRECTORY = "/config/cache";
      KOPIA_LOG_DIR = "/config/logs";
      KOPIA_MIN_SEVERITY = "warning";
      KOPIA_WEBDAV_URL = "http://openlist:80/dav/main";
    };
    environmentFiles = [ config.sops.templates."kopia.env".path ];
    dependsOn = [ "openlist" ];
    networks = [ "homelab" ];
    ports = [ "${address}:51515:51515/tcp" ];
    volumes = [
      "${cacheVolume}:/config/cache"
      "${logDir}:/config/logs"
      "/data:/backup/data:ro"
      "${shared + "/policy.json"}:/config/policy.json:ro"
      "${shared + "/entrypoint.sh"}:/app/scripts/entrypoint.sh:ro"
    ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "kopia";
      "homepage.icon" = "kopia.svg";
      "homepage.href" = "http://${address}:51515/tasks";
      "homepage.description" = "备份服务";
    };
  };

  # 就绪语义：dependsOn 只保证先启动 openlist，不等它健康。
  # 不在 ExecStartPre 里轮询健康：那会阻塞 unit 的启动任务，进而拖长整次 switch，
  # 超过 deploy-rs 的确认窗口就误判成「未确认」并回滚（2026-11-03 实测）。
}
