{
  config,
  lib,
  mylib,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.shelken.secrets;
in
{
  config = mkIf cfg.enable {
    sops.secrets."drive/s3/url" = mylib.mkDefaultSecret { };
    sops.secrets."drive/s3/access_key_id" = mylib.mkDefaultSecret { };
    sops.secrets."drive/s3/secret_access_key" = mylib.mkDefaultSecret { };

    sops.templates."rclone.conf" = {
      content = ''
        [drive-s3]
        type = s3
        access_key_id = ${config.sops.placeholder."drive/s3/access_key_id"}
        endpoint = ${config.sops.placeholder."drive/s3/url"}
        secret_access_key = ${config.sops.placeholder."drive/s3/secret_access_key"}
        provider = Other
      '';
      path = "${config.xdg.configHome}/rclone/rclone.conf";
      # owner = "shelken";
      mode = "0500";
    };

    # xdg.configFile = {
    #   "rclone/rclone.conf" = {
    #     source = "${config.sops.templates."rclone.conf".path}";
    #   };
    # };

  };
}
