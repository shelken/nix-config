{ self, ... }:
let
  hostname = "yuuko";
in
{
  imports = with self.modules.darwin; [
    desktop
    homelab
  ];

  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    secrets.enable = true;
  };
}
