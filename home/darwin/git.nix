{
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf;
  cfg = config.shelken.secrets;
in {
  config = mkIf cfg.enable {
    programs = {
      gh = {
        enable = true;
      };
      bash.initExtra = ''
        export GITHUB_TOKEN="$(cat ${config.sops.secrets."github/cli-token".path})"
      '';
      zsh.initExtra = ''
        export GITHUB_TOKEN="$(cat ${config.sops.secrets."github/cli-token".path})"
      '';
    };
  };
}
