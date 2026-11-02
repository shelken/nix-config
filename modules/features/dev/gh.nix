# GitHub CLI：gh、git 凭据 helper 与 gh-stack 扩展
{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.gh ];

  flake.modules.homeManager.gh =
    { pkgs, ... }:
    {
      # gh 本体由共享工具登记表提供（shelken.dev.tools，ADR 0003）；
      # 凭据 helper 配置保留在此，与 gh 二进制的来源解耦
      home.packages = with pkgs; [
        gh-markdown-preview
        gh-stack
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
