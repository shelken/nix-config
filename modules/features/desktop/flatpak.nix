{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.flatpak ];

  flake.modules.nixos.flatpak.services.flatpak.enable = true;
}
