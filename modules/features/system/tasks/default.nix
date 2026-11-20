{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.tasks ];

  flake.modules.darwin.tasks.imports = [ ./_framework.nix ];

  flake.modules.homeManager.tasks.imports = [
    ./_user-tasks.nix
    ./_notify.nix
  ];
}
