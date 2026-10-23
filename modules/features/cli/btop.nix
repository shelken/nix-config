# btop：系统监视器
{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.btop ];

  flake.modules.homeManager.btop = {
    # replacement of htop/nmon
    programs.btop = {
      enable = true;
      settings = {
        theme_background = false; # make btop transparent
      };
    };
  };
}
