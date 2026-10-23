# Tinycast 快捷启动与应用唤起：cask、系统快捷键 defaults、CLI 脚本与启动器命令同步
# tinycast 是显示器/应用遥控 cask，只有接显示器的桌面机才有意义 → desktop（与基线一致）
{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.tinycast ];

  flake.modules.darwin.tinycast.homebrew.casks = [ "shelken/tap/tinycast" ];

  flake.modules.homeManager.tinycast.imports = [ ./_hm.nix ];
}
