{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.tinycast ];

  flake.modules.darwin.tinycast.homebrew.casks = [ "shelken/tap/tinycast" ];

  flake.modules.homeManager.tinycast.imports = [ ./_hm.nix ];
}
