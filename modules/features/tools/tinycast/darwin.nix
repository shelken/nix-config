# Tinycast 快捷启动与应用唤起：cask、系统快捷键 defaults、CLI 脚本与启动器命令同步
# 脚本与 defaults 所有 darwin 主机都有（原 home/darwin/scripts/tinycast.nix）；
# 应用本体是显示器/应用遥控 cask，只有接显示器的桌面机需要 → desktop
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.tinycast ];

  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.tinycast-app ];

  flake.modules.darwin.tinycast-app.homebrew.casks = [ "shelken/tap/tinycast" ];

  flake.modules.homeManager.tinycast.imports = [ ./_hm.nix ];
}
