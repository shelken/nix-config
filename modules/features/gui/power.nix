# 电源管理：power-profiles-daemon、upower
# 笔记本与桌面机才需要 → nixos.gui
{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.power ];

  flake.modules.nixos.power.services = {
    power-profiles-daemon.enable = true;
    upower.enable = true;
  };
}
