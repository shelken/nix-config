{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.bash ];

  flake.modules.homeManager.bash = {
    programs.bash = {
      enable = true;
      enableCompletion = true;
    };
  };
}
