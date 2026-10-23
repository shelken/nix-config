# GitHub CLI：gh 与 git 凭据 helper（home/base/tui/git.nix 迁入）
{
  flake.modules.homeManager.gh =
    { pkgs, ... }:
    {
      programs.gh = {
        enable = true;
        gitCredentialHelper.enable = false;
      };
      home.packages = with pkgs; [
        gh-markdown-preview
      ];
      programs.git.settings.credential = {
        # 加空白是先清除system定义的osxkeychain
        "https://github.com" = {
          helper = [
            ""
            "!${pkgs.gh}/bin/gh auth git-credential"
          ];
        };
        "https://gist.github.com" = {
          helper = [
            ""
            "!${pkgs.gh}/bin/gh auth git-credential"
          ];
        };
        "https://mirrors.tuna.tsinghua.edu.cn" = {
          helper = [
            ""
            "!${pkgs.gh}/bin/gh auth git-credential"
          ];
        };
      };
    };
}
