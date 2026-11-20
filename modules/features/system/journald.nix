{ config, ... }:
{
  flake.modules.nixos.server.imports = [ config.flake.modules.nixos.journald ];

  flake.modules.nixos.journald = {
    services.journald.settings.Journal.SystemMaxUse = "2G";
  };
}
