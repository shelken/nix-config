_: let
  hostname = "lingmac";
in {
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    tools.hammerspoon.enable = true;
  };
}
