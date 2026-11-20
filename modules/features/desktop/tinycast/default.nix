{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.tinycast ];

  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.tinycast-app ];

  flake.modules.darwin.tinycast-app.homebrew.casks = [ "shelken/tap/tinycast" ];

  flake.modules.homeManager.tinycast.imports = [ ./_hm.nix ];
}
