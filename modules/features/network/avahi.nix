{ config, ... }:
{
  flake.modules.nixos.tui.imports = [ config.flake.modules.nixos.avahi ];

  flake.modules.nixos.avahi = {
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      settings.publish = {
        disable-publishing = false;
        publish-addresses = true;
        publish-domain = true;
        disable-user-service-publishing = false;
      };
    };
  };
}
