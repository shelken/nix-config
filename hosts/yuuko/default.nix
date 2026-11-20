{ self, ... }:
let
  hostname = "yuuko";
in
{
  imports = with self.modules.darwin; [
    desktop
    homelab
    ai
    lima-host
  ];

  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    secrets.enable = true;
    limaHost.node = "yuuko-k8s";
  };
}
