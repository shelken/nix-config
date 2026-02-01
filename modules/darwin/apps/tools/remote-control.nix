{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.tools.remote-control;
in
{
  options.shelken.tools.remote-control = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      brews = [
      ];
      casks = [
        "windows-app"
      ];
    };
  };
}
