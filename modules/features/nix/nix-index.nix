{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.nix-index ];

  flake.modules.homeManager.nix-index =
    { config, ... }:
    {
      programs.nix-index = {
        enable = true;
        enableZshIntegration = config.programs.zsh.enable;
        enableBashIntegration = config.programs.bash.enable;
      };
    };
}
