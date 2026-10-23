# 网络基础：mDNS（avahi）与国内 NTP
# 所有 NixOS 主机都需要 → nixos.core
{ config, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.networking ];

  flake.modules.nixos.networking = {
    # Network discovery, mDNS
    # With this enabled, you can access your machine at <hostname>.local
    # it's more convenient than using the IP address.
    # https://avahi.org/
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        domain = true;
        userServices = true;
      };
    };
    # Use an NTP server located in the mainland of China to synchronize the system time
    networking.timeServers = [
      "ntp.aliyun.com" # Aliyun NTP Server
      "ntp.tencent.com" # Tencent NTP Server
    ];
  };
}
