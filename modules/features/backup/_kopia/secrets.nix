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
      # WebDAV 入口域名：secret 只存裸域名，scheme 与 /dav 前缀在模板里拼
      secrets.kopia-main-domain = mylib.mkDefaultSecret { key = "main-domain"; };
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
                "url": "https://drive.${config.sops.placeholder.kopia-main-domain}/dav/backup/kopia/main",
                "username": "${config.sops.placeholder.kopia-webdav-username}",
                "password": "${config.sops.placeholder.kopia-webdav-password}"
              }
            },
            "caching": {
              "cacheDirectory": "${config.xdg.cacheHome}/kopia/main",
              "maxCacheSize": 1073741824,
              "maxMetadataCacheSize": 1073741824,
              "maxListCacheDuration": 30
             },
            "hostname": "${hostname}",
            "username": "${myvars.username}",
            "description": "Repository in WebDAV: drive.${config.sops.placeholder.kopia-main-domain} /dav/backup/kopia/main",
            "enableActions": false,
            "formatBlobCacheDuration": 900000000000
          }
        '';
        mode = "0500";
      };
    };
  };
}
