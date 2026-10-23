{ self, ... }:
let
  hostname = "lingmac";
in
{
  imports = [ self.modules.darwin.gui ];

  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    wm.aerospace.enable = true;
    tools.hammerspoon.enable = false;
  };
}
