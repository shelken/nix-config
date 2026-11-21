{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.zoxide ];

  flake.modules.homeManager.zoxide =
    { config, ... }:
    {
      programs.zoxide = {
        enable = true;
        enableBashIntegration = config.programs.bash.enable;
        enableZshIntegration = config.programs.zsh.enable;
        enableNushellIntegration = config.programs.nushell.enable;
      };
    };
}
