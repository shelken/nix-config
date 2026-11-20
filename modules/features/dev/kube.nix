{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.kube ];

  flake.modules.homeManager.kube = {
    home.file.".kube/config" = {
      text = "";
      force = true;
    };
  };
}
