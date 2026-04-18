{
  config,
  lib,
  mylib,
  myvars,
  hostname,
  ...
}:
let
  cfg = config.shelken.backup;
in
{
  config = lib.mkIf cfg.enable {
    shelken.tools.backup.enable = true;
    shelken.secrets.enable = true;

    sops.secrets.kopia-password = mylib.mkDefaultSecret { key = "kopia/password"; };
    sops.secrets.kopia-s3-host = mylib.mkDefaultSecret { key = "drive/s3/host"; };
    sops.secrets.kopia-s3-access-key-id = mylib.mkDefaultSecret { key = "drive/s3/access_key_id"; };
    sops.secrets.kopia-s3-secret-access-key = mylib.mkDefaultSecret {
      key = "drive/s3/secret_access_key";
    };

    ## NOTE: kopia 的 s3 与文件系统存储结构不同，因此不同 repo 创建的无法直接连接，必须使用不同 repo
    ## 不同 repo 之间同步使用子命令 `repository sync-to`
    sops.templates."kopia-repository.config" = {
      content = ''
        {
          "storage": {
            "type": "s3",
            "config": {
              "bucket": "kopia",
              "prefix": "main/",
              "endpoint": "${config.sops.placeholder.kopia-s3-host}",
              "doNotUseTLS": false,
              "accessKeyID": "${config.sops.placeholder.kopia-s3-access-key-id}",
              "secretAccessKey": "${config.sops.placeholder.kopia-s3-secret-access-key}"
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
          "description": "Repository in S3: ${config.sops.placeholder.kopia-s3-host} kopia:main/",
          "enableActions": false,
          "formatBlobCacheDuration": 900000000000
        }
      '';
      mode = "0500";
    };
  };
}
