# GitHub CLI：gh（agent-gh 包装，见 README）、git 凭据 helper 与 gh-stack 扩展
{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.gh ];

  flake.modules.homeManager.gh =
    { pkgs, myvars, ... }:
    {
      # 登记表里的 gh 就是包装：宿主与沙箱同一份声明。没有 AGENT_GITHUB_TOKEN 时等同真 gh
      shelken.dev.tools.gh.package =
        pkgs:
        import ./_package.nix {
          inherit pkgs;
          owner = myvars.username;
        };
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
