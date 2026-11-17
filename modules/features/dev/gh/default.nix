# GitHub CLI：gh（agent-gh 包装，见 README）、git 凭据 helper 与 gh-stack 扩展
{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.gh ];
  # gh-dash 只在 darwin 上用 → darwin.core
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.gh-dash ];

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

  flake.modules.homeManager.gh-dash = {
    programs.gh-dash.enable = true; # catppuccin 主题经 autoEnable 注入
    # 仅收编与 v4.25.2 内置默认有差异的项；其余交给 gh-dash 内置默认
    programs.gh-dash.settings = {
      # prSections 是列表覆盖语义：默认 3 个 section 会被替换，需完整重述
      prSections = [
        {
          title = "Pull Requests";
          filters = "is:open";
        } # 自定义：顶部加全部 PR 总览
        {
          title = "My Pull Requests";
          filters = "is:open author:@me";
        }
        {
          title = "Needs My Review";
          filters = "is:open review-requested:@me";
        }
        {
          title = "Involved";
          filters = "is:open involves:@me -author:@me";
        }
      ];
      keybindings.universal = [
        {
          key = "pgup";
          builtin = "pageUp";
        } # 自定义：翻页键
        {
          key = "pgdown";
          builtin = "pageDown";
        }
      ];
    };
  };
}
