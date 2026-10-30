# 网络基础：国内 NTP
# 所有 NixOS 主机的默认值 → nixos.core；位于国外的主机在自己的配置里覆盖。mDNS 见 avahi.nix
{ config, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.networking ];

  flake.modules.nixos.networking = {
    # Use an NTP server located in the mainland of China to synchronize the system time
    networking.timeServers = [
      "ntp.aliyun.com" # Aliyun NTP Server
      "ntp.tencent.com" # Tencent NTP Server
    ];
  };
}
