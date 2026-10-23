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

    dev.container.enable = true;

    network.fl-clash.enable = true;

    suites.desktop.enable = true;

    wm.aerospace.enable = true;
  };
}
