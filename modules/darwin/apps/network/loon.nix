{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.network.loon;
in
{
  options.shelken.network.loon = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      casks = [
        "loon"
      ];
      brews = [
      ];
    };
    launchd.user.agents.loon = {
      command = ''"/Applications/Loon.app/Contents/MacOS/Loon"'';
      serviceConfig.RunAtLoad = true;
    };
  };
}
