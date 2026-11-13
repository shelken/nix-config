{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.ai ];

  flake.modules.darwin.ai = {
    homebrew = {
      taps = [ ];
      casks = [
        # "ollama-app"

        "openusage"

        "alma"
        # "osaurus"
      ];
    };
  };
}
