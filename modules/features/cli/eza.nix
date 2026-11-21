{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.eza ];

  flake.modules.homeManager.eza = {
    programs.eza = {
      enable = true;
      git = true;
      icons = "auto";
    };

    home.shellAliases = {
      ll = "eza --icons -l -T -L=1";
    };
  };
}
