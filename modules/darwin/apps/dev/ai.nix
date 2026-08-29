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
      brews = [
      ];
      casks = [
        # "ollama-app"
        "lm-studio"

        "agentsview"

        "alma"
        # "osaurus"
      ];
    };
  };
}
