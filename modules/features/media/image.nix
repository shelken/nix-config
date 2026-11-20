{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.image ];

  flake.modules.darwin.image.homebrew.casks = [
    "imageoptim"
    "upic"
  ];
}
