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

  home.shellAliases = {
    pi = "sec-run pi";
  };

  # ponytail 扩展配置: 隐藏状态栏显示, 保留规则注入
  # 可编辑：软链到仓库源文件 home/base/gui/dev/ai/ponytail/config.json
  home.file.".config/ponytail/config.json" = {
    source = config.lib.file.mkOutOfStoreSymlink "${ponytailDir}/config.json";
    force = true;
  };

  # 权限防护规则软链到 omp 目录下的 permissions.yaml（与 omp 共享同一份规则库）
  home.file.".pi/agent/permissions.yaml" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/base/gui/dev/ai/omp/permissions.yaml";
    force = true;
  };
  shelken.backup.app.pi = [
    "${config.home.homeDirectory}/.pi"
  ];
  programs.zsh.initContent = shellInit;
}
