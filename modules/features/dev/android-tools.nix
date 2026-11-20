{ config, ... }:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.android-tools ];
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.android-tools ];

  flake.modules.homeManager.android-tools =
    { pkgs, ... }:
    {
      programs.television.enable = true;
      home.packages = with pkgs; [
        android-tools
        scrcpy
      ];
    };
}
