{ config, ... }:
{
  flake.modules.nixos.server.imports = [ config.flake.modules.nixos.zram ];

  flake.modules.nixos.zram = {
    zramSwap.enable = true;
  };
}
