# mDNS（avahi）：局域网里用 <hostname>.local 访问本机
# 开发机与桌面机才需要 → nixos.tui；公网服务器不广播自己
{ config, ... }:
{
  flake.modules.nixos.tui.imports = [ config.flake.modules.nixos.avahi ];

  flake.modules.nixos.avahi = {
    # With this enabled, you can access your machine at <hostname>.local
    # it's more convenient than using the IP address.
    # https://avahi.org/
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
