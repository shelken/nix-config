{ config, ... }:
let
  address = config.shelken.vpsContainers.tailscaleAddress;
  logDir = "/data/docker/kopia/logs";

  # Compose 的命名卷带项目名前缀，而这个卷是上次部署时创建的：
  # 切换前必须按 docs/user-guide/06-containers.md 核对线上实际卷名，
  # 对不上只会丢一份缓存与对账指纹，kopia 会重新对账
  cacheVolume = "homelab-compose_kopia_cache";
in
{
  systemd.tmpfiles.rules = [
    "d ${logDir} 0755 root root -"
  ];

  # 仓库口令、通知 Webhook、openlist 的 WebDAV 凭据都只在密文里
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
    '';
    restartUnits = [ "docker-kopia.service" ];
  };

  # 仓库配置里有 WebDAV 凭据，只能由模板在激活时渲染；
  # 其余字段与 Compose 里的 repository.config 一致
  sops.templates."kopia-repository.config" = {
    content = ''
      {
        "storage": {
          "type": "webdav",
          "config": {
            "url": "http://openlist:80/dav/main",
            "username": "${config.sops.placeholder."openlist/webdav-username"}",
            "password": "${config.sops.placeholder."openlist/webdav-password"}"
          }
        },
        "caching": {
          "cacheDirectory": "/app/cache",
          "maxCacheSize": 5242880000,
          "maxMetadataCacheSize": 5242880000,
          "maxListCacheDuration": 30
        }
      }
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
    };
    environmentFiles = [ config.sops.templates."kopia.env".path ];
    # 只给启动顺序与依赖；旧 Compose 等的是 openlist 的「健康」状态，
    # 所以 systemd unit 里还要在启动前真的等到它 healthy
    dependsOn = [ "openlist" ];
    networks = [ "homelab" ];
    ports = [ "${address}:51515:51515/tcp" ];
    volumes = [
      "${cacheVolume}:/config/cache"
      "${logDir}:/config/logs"
      "/data:/backup/data:ro"
      "${config.sops.templates."kopia-repository.config".path}:/config/repository.config:ro"
      "${./policy.json}:/config/policy.json:ro"
      "${./entrypoint.sh}:/app/scripts/entrypoint.sh:ro"
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
  # 改成让 kopia 自己失败重试：仓库连不上时 entrypoint 立刻退出 1，
  # Restart=always + RestartSec=10s 会一直重试到 openlist 能用为止
  systemd.services.docker-kopia = {
    after = [ "docker-network-homelab.service" ];
    requires = [ "docker-network-homelab.service" ];
  };
}
