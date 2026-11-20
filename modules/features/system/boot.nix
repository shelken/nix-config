{ config, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.boot ];

  flake.modules.nixos.boot =
    { lib, ... }:
    {
      boot.loader.systemd-boot = {
        configurationLimit = lib.mkDefault 10;
        consoleMode = lib.mkDefault "max";
      };
    };
}
