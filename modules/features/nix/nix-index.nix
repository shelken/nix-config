{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.nix-index ];

  flake.modules.homeManager.nix-index.programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };
}
