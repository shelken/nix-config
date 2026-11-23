{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.carapace ];

  flake.modules.homeManager.carapace =
    { config, ... }:
    {
      programs.carapace = {
        enable = true;
        enableZshIntegration = config.programs.zsh.enable;
        enableBashIntegration = config.programs.bash.enable;
        enableNushellIntegration = config.programs.nushell.enable;
        environment = {
          CARAPACE_EXCLUDES = "kubectl";
        };
      };
    };
}
