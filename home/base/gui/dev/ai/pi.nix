{ pkgs, config, ... }:
let
  shellInit = ''
    # for extension pi-powerline-footer
    export POWERLINE_NERD_FONTS=1
  '';
in
{
  home.packages = with pkgs; [
    # rtk
    pandoc # for npm:pi-markdown-preview
    mermaid-cli # for npm:pi-markdown-preview
  ];

  # ponytail 扩展配置: 隐藏状态栏显示, 保留规则注入
  home.file.".config/ponytail/config.json".text = builtins.toJSON {
    hideStatus = true;
    quietStartup = true;
  };
  shelken.backup.app.pi = [
    "${config.home.homeDirectory}/.pi"
  ];
  programs.zsh.initContent = shellInit;
}
