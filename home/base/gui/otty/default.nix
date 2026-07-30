{ config, ... }:
let
  ottyTomlPath = "${config.home.homeDirectory}/nix-config/home/base/gui/otty/config.toml";
in
{
  xdg.configFile."otty/config.toml" = {
    source = config.lib.file.mkOutOfStoreSymlink ottyTomlPath;
    force = true;
  };
}
