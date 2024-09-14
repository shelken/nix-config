{
  lib,
  mylib,
  config,
  pkgs,
  # options,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.wm.iceBar;
in {
  options.shelken.wm.iceBar = {
    enable = mkBoolOpt false "Whether or not to enable iceBar.";
  };

  config = mkIf cfg.enable {
    # xdg.configFile = {
    #   "aerospace/aerospace.toml" = {
    #     source = ./aerospace/aerospace.toml;
    #   };
    # };

    home.packages = with pkgs; [
      ice-bar
    ];
  };
}
