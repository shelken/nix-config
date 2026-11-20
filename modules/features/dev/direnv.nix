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
          hide_env_diff = true;
        };
      };
    };
  };
}
