{
  lib,
  mylib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.suites.game;
in {
  options.shelken.suites.game = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    shelken.game.winx.enable = true;
    # homebrew = {
    #   casks = [
    #   ];
    #   masApps = {
    #   };
    # };
  };
}
