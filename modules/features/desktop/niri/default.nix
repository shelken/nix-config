{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.niri ];

  flake.modules.nixos.niri =
    { inputs, pkgs, ... }:
    {
      imports = [
        inputs.niri.nixosModules.niri
        { programs.niri.enable = true; }
      ];

      programs.niri.package = pkgs.niri;
    };

  flake.modules.homeManager.niri =
    {
      inputs,
      pkgs,
      ...
    }:
    {
      imports = [ (import ./_keybindings.nix inputs.niri) ];

      home.packages = with pkgs; [
        xwayland-satellite
      ];

      shelken.desktop.sessionScript = pkgs.writeScript "init-session" ''
        systemctl --user is-active niri.service && systemctl --user stop niri.service
        /run/current-system/sw/bin/niri-session
      '';
    };
}
