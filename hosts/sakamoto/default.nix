{ self, ... }:
let
  hostname = "sakamoto";
in
{
  imports = with self.modules.darwin; [
    desktop
    homelab
    utm
  ];

  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    secrets.enable = true;
    limaHost = {
      node = "sakamoto-k8s";
      externalDisk = "/Volumes/sakamoto-data";
    };
  };
}
