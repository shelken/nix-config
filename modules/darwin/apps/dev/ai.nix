{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.dev.ai;
in
{
  options.shelken.dev.ai = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      taps = [
        {
          name = "stablyai/orca";
          trusted = true;
        }
      ];
      brews = [
        "media-control" # computer-use 控制
      ];
      casks = [
        # "ollama-app"
        "lm-studio"

        "stablyai/orca/orca"

        "openusage"

        "agentsview"

        "alma"
        # "osaurus"
      ];
    };
  };
}
