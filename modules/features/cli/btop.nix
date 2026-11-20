{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.btop ];

  flake.modules.homeManager.btop = {
    programs.btop = {
      enable = true;
      settings = {
        theme_background = false;
      };
    };
  };
}
