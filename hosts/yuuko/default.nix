{ self, ... }:
let
  hostname = "yuuko";
in
{
  imports = with self.modules.darwin; [
    gui
    homelab
  ];

  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    dev.container.enable = true;

    network.fl-clash.enable = true;

    suites.desktop.enable = true;

    wm.aerospace.enable = true;
  };
}
