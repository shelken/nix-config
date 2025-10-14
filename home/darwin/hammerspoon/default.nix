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
    # home.activation.HammerspoonLoginItem = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    #   mylib.mkLoginItemString { app_name = "Hammerspoon"; }
    # );
    # launchd.agents.hammerspoon = mylib.mkLaunchCommand {
    #   name = "hammerspoon";
    #   commandFile = "/Applications/Hammerspoon.app/Contents/MacOS/Hammerspoon";
    # };
    home.file = {
      ".hammerspoon/Spoons/SpoonInstall.spoon" = {
        source = pkgs.fetchzip {
          url = "https://github.com/Hammerspoon/Spoons/raw/master/Spoons/SpoonInstall.spoon.zip";
          hash = "sha256-3f0d4znNuwZPyqKHbZZDlZ3gsuaiobhHPsefGIcpCSE=";
        };
      };
      # ".hammerspoon/Spoons/InputSourceSwitch.spoon" = {
      #   source = pkgs.fetchzip {
      #     url = "https://github.com/Hammerspoon/Spoons/raw/master/Spoons/InputSourceSwitch.spoon.zip";
      #     hash = "sha256-Gb+IpUHqIOVxNBOp7wjs1nQ9AIvtPNe7Vx2OemN8NO0=";
      #   };
      # };
      ".hammerspoon/Spoons/PaperWM.spoon" = {
        source = pkgs.fetchFromGitHub {
          owner = "mogenson";
          repo = "PaperWM.spoon";
          rev = "c7247801b2a3f4aac63f475ef677b367a310b8fd";
          fetchSubmodules = false;
          sha256 = "sha256-or92pm1rEzg0iTwTpqpzSjStO/TgSDa3n9B+earlGrA=";
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
