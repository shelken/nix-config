{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.shelken.secrets;
  shellInit = ''
    export GH_TOKEN="$(cat ${config.sops.secrets."github/cli-token".path})"
    export GITHUB_TOKEN="$(cat ${config.sops.secrets."github/cli-token".path})"
  '';
in
{
  config = mkIf cfg.enable {
    programs.gh = {
      enable = true;
      gitCredentialHelper.enable = false;
    };
    programs.bash.initExtra = shellInit;
    programs.zsh.initContent = shellInit;
    programs.git.extraConfig.credential = {
      # 加空白是先清除system定义的osxkeychain
      "https://github.com" = {
        helper = [
          ""
          "!gh auth git-credential"
        ];
      };
      "https://gist.github.com" = {
        helper = [
          ""
          "!gh auth git-credential"
        ];
      };
      "https://mirrors.tuna.tsinghua.edu.cn" = {
        helper = [
          ""
          "!gh auth git-credential"
        ];
      };
    };
  };
}
