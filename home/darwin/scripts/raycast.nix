{ config, ... }:
let
  customCommandsPath = "${config.home.homeDirectory}/nix-config/home/darwin/scripts/raycast";
in
{
  xdg.configFile."raycast/custom-commands".source =
    config.lib.file.mkOutOfStoreSymlink customCommandsPath;
}
