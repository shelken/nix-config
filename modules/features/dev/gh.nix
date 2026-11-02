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
      ];
      # 只链接 gh-stack 一个扩展目录，不启用 programs.gh：它会接管 config.yml 与凭据 helper，
      # 与登记表提供的 gh 和下面的凭据配置重复。目录结构同 programs.gh.extensions：<扩展名>/ 下放同名可执行文件
      xdg.dataFile."gh/extensions/gh-stack".source = "${pkgs.gh-stack}/bin";
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
