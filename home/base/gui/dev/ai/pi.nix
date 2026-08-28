{ pkgs, config, ... }:
let
  ponytailDir = "${config.home.homeDirectory}/nix-config/home/base/gui/dev/ai/ponytail";
  shellInit = ''
    # for extension pi-powerline-footer
    export POWERLINE_NERD_FONTS=1
    # for pi-fff
    export FFF_ENABLE_HOME_SCAN=0
  '';
in
{
  home.packages = with pkgs; [
    mermaid-cli # for npm:pi-markdown-preview
  ];

  # ponytail 扩展配置: 隐藏状态栏显示, 保留规则注入
  # 可编辑：软链到仓库源文件 home/base/gui/dev/ai/ponytail/config.json
  home.file.".config/ponytail/config.json" = {
    source = config.lib.file.mkOutOfStoreSymlink "${ponytailDir}/config.json";
    force = true;
  };
  shelken.backup.app.pi = [
    "${config.home.homeDirectory}/.pi"
  ];
  programs.zsh.initContent = shellInit;
}
