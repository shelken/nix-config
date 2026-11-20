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
      secrets.kopia-main-domain = mylib.mkDefaultSecret { key = "main-domain"; };
      secrets.kopia-webdav-username = mylib.mkDefaultSecret { key = "drive/webdav/username"; };
      secrets.kopia-webdav-password = mylib.mkDefaultSecret {
        key = "drive/webdav/password";
      };

      ## atomicWrites：直接 PUT 到最终名，绕开 openlist 偶发「MOVE 返回成功却没改名」的问题，见 shelken/home-ops#1763
      templates."kopia-repository.config" = {
        content = ''
          {
            "storage": {
              "type": "webdav",
              "config": {
                "url": "https://drive.${config.sops.placeholder.kopia-main-domain}/dav/backup/kopia/main",
                "username": "${config.sops.placeholder.kopia-webdav-username}",
                "password": "${config.sops.placeholder.kopia-webdav-password}",
                "atomicWrites": true
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
