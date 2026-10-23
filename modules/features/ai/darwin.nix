{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.ai ];

  flake.modules.darwin.ai = {
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
        "stablyai/orca/orca"

        "openusage"

        "agentsview"

        "alma"
        # "osaurus"
      ];
    };
  };
}
