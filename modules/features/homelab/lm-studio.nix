{ config, ... }:
{
  flake.modules.darwin.homelab.imports = [ config.flake.modules.darwin.lm-studio ];

  flake.modules.darwin.lm-studio.homebrew.casks = [ "lm-studio" ];

  flake.modules.homeManager.lm-studio.home.sessionPath = [ "$HOME/.lmstudio/bin" ];
}
