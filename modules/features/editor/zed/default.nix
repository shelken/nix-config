{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.zed ];

  flake.modules.darwin.zed.homebrew.casks = [ "zed" ];

  flake.modules.homeManager.zed = import ./_hm.nix;
}
