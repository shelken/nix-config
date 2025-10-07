{
  lib,
  mylib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.tools.hammerspoon;
in {
  options.shelken.tools.hammerspoon = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    home.file = {
      ".hammerspoon/Spoons/SpoonInstall.spoon" = {
        source = pkgs.fetchzip {
          url = "https://github.com/Hammerspoon/Spoons/raw/master/Spoons/SpoonInstall.spoon.zip";
          hash = "sha256-3f0d4znNuwZPyqKHbZZDlZ3gsuaiobhHPsefGIcpCSE=";
        };
      };
      ".hammerspoon/config" = {
        source = ./config;
        recursive = true;
      };
      ".hammerspoon/init.lua" = {
        source = ./init.lua;
      };
    };
  };
}
