{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.power ];

  flake.modules.nixos.power.services = {
    power-profiles-daemon.enable = true;
    upower.enable = true;
  };
}
