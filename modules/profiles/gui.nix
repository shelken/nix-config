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
    ];
    home-manager.sharedModules = [ ../../home/linux/gui ];
  };

  flake.modules.homeManager.gui.imports = [ ../../home/base/gui ];
}
