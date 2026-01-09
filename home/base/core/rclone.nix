{
  config,
  lib,
  mylib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.shelken.secrets;
in
{
  config = mkIf cfg.enable {
    sops.secrets."drive/s3/url" = mylib.mkDefaultSecret { };
    sops.secrets."drive/url" = mylib.mkDefaultSecret { };
    sops.secrets."drive/s3/access_key_id" = mylib.mkDefaultSecret { };
    sops.secrets."drive/s3/secret_access_key" = mylib.mkDefaultSecret { };
    sops.secrets."drive/rclone/pass" = mylib.mkDefaultSecret { };

    sops.templates."rclone.conf" = {
      content = ''
        [drive-s3]
        type = s3
        access_key_id = ${config.sops.placeholder."drive/s3/access_key_id"}
        endpoint = ${config.sops.placeholder."drive/s3/url"}
        secret_access_key = ${config.sops.placeholder."drive/s3/secret_access_key"}
        provider = Other
        [drive-dav]
        type = webdav
        url = ${config.sops.placeholder."drive/url"}/dav
        vendor = other
        user = rclone
        pass = @RCLONE_DRIVE_DAV_PASSWORD_OBSCURED@
      '';
      mode = "0500";
    };

    # 重新调整密码
    home.activation.postRclone = lib.hm.dag.entryAfter [ "sops-nix" ] ''
      RCLONE_PATH=${config.xdg.configHome}/rclone/rclone.conf
      RCLONE_TEMPLATE_PATH=${config.xdg.configHome}/sops-nix/secrets/rendered/rclone.conf

      # 检查模板文件是否存在，不存在则跳过（不能用 exit，会终止整个 activation）
      if [ -f "$RCLONE_TEMPLATE_PATH" ]; then
        cp -f $RCLONE_TEMPLATE_PATH $RCLONE_PATH

        RCLONE_DRIVE_DAV_PASSWORD=$(cat ${config.sops.secrets."drive/rclone/pass".path})
        RCLONE_DRIVE_DAV_PASSWORD_OBSCURED=$(${pkgs.rclone}/bin/rclone obscure "$RCLONE_DRIVE_DAV_PASSWORD")

        ${pkgs.gnused}/bin/sed -i \
              -e "s|@RCLONE_DRIVE_DAV_PASSWORD_OBSCURED@|$RCLONE_DRIVE_DAV_PASSWORD_OBSCURED|g" \
              $RCLONE_PATH
        chmod 600 $RCLONE_PATH
      fi
    '';

  };
}
