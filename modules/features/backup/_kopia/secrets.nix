{
  config,
  lib,
  mylib,
  myvars,
  hostname,
  ...
}:
{
  config = {
    assertions = [
      {
        assertion = config.shelken.secrets.enable;
        message = "shelken.backup: 开启备份需要主机启用 secrets (shelken.secrets.enable = true)";
      }
    ];

    sops = {
      secrets.kopia-password = mylib.mkDefaultSecret { key = "kopia/password"; };
      secrets.kopia-webdav-url = mylib.mkDefaultSecret { key = "drive/url"; };
      secrets.kopia-webdav-username = mylib.mkDefaultSecret { key = "drive/webdav/username"; };
      secrets.kopia-webdav-password = mylib.mkDefaultSecret {
        key = "drive/webdav/password";
      };

      ## NOTE: kopia 仓库存储结构随后端类型而异（S3 与 WebDAV 互不兼容），
      ## 载入旧库的数据不能直接连新库，迁移需在旧库上执行 repository sync-to
      templates."kopia-repository.config" = {
        content = ''
          {
            "storage": {
              "type": "webdav",
              "config": {
                "url": "${config.sops.placeholder.kopia-webdav-url}/dav/backup/kopia/main",
                "username": "${config.sops.placeholder.kopia-webdav-username}",
                "password": "${config.sops.placeholder.kopia-webdav-password}"
              }
            },
            "caching": {
              "cacheDirectory": "${config.xdg.cacheHome}/kopia/main",
              "maxCacheSize": 5242880000,
              "maxMetadataCacheSize": 5242880000,
              "maxListCacheDuration": 30
             },
            "hostname": "${hostname}",
            "username": "${myvars.username}",
            "description": "Repository in WebDAV: ${config.sops.placeholder.kopia-webdav-url} /dav/backup/kopia/main",
            "enableActions": false,
            "formatBlobCacheDuration": 900000000000
          }
        '';
        mode = "0500";
      };
    };
  };
}
