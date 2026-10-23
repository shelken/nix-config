# direnv：nix-direnv 集成
{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.direnv ];

  flake.modules.homeManager.direnv = {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableZshIntegration = true;
      config = {
        global = {
          # Hides the rather large block of text that is usually printed when entering the environment.direnv version > 2.34
          hide_env_diff = true;
        };
      };
    };
  };
}
