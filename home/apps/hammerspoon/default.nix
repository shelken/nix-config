{
  lib,
  mylib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.tools.hammerspoon;
  origin_init = builtins.readFile ./init.lua;
  cfg_wm = config.shelken.tools.hammerspoon.wm;
in
{
  options.shelken.tools.hammerspoon = {
    enable = mkBoolOpt false "Whether or not to enable.";
    wm.enable = mkBoolOpt false "Whether or not to enable.";
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
        text = lib.concatStrings (
          [
            origin_init
          ]
          ++ (lib.optionals (cfg_wm.enable) ''
            -- 启用窗口管理
            require("config.paperwm") -- 窗口管理
          '')
        );
      };
    };
  };
}
