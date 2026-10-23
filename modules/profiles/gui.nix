# gui：tui + 桌面环境与图形应用
{ config, ... }:
let
  inherit (config.flake.modules) darwin nixos;
in
{
  flake.modules.darwin.gui.imports = [ darwin.tui ];

  flake.modules.nixos.gui = {
    imports = [
      ../nixos/desktop.nix
      nixos.tui
      config.flake.modules.nixos.fonts
    ];
    shelken.fonts.enable = true;
    home-manager.sharedModules = [ ../../home/linux/gui ];
  };
}
