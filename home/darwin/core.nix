{
  myvars,
  pkgs,
  ...
}:
{
  home.homeDirectory = "/Users/${myvars.username}";
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
  home.packages = with pkgs; [
    glab # gitlab cli

    rclone # web driver
    # superfile # like yazi
    comma # use `, cowsay hello` == `nix run nixpkgs#cowsay -- hello`

    nix-search-tv # 查询各种（nixpkgs,home-manager,nur)下的包或选项

    # 仅暴露 timeout 一个命令，闭包约 2MB，macOS 无自带 timeout
    (runCommand "timeout" { } ''
      mkdir -p $out/bin
      ln -s ${coreutils}/bin/timeout $out/bin/timeout
    '')
  ];
  home.shellAliases = {
    ns = "nix-search-tv print | fzf --preview 'nix-search-tv preview {}' --scheme history";
  };
}
