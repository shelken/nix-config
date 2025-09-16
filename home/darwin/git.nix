{
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf;
  cfg = config.shelken.secrets;
in {
  imports = [
    ../apps/lazygit
  ];
  config = mkIf cfg.enable {
    programs = {
      gh = {
        enable = true;
        gitCredentialHelper.enable = false;
      };
      bash.initExtra = ''
        export GITHUB_TOKEN="$(cat ${config.sops.secrets."github/cli-token".path})"
      '';
      zsh.initContent = ''
        export GITHUB_TOKEN="$(cat ${config.sops.secrets."github/cli-token".path})"
      '';
      git.extraConfig.credential = {
        # 加空白是先清除system定义的osxkeychain
        "https://github.com" = {
          helper = ["" "!gh auth git-credential"];
        };
        "https://gist.github.com" = {
          helper = ["" "!gh auth git-credential"];
        };
        "https://mirrors.tuna.tsinghua.edu.cn" = {
          helper = ["" "!gh auth git-credential"];
        };
      };
    };
  };
}
