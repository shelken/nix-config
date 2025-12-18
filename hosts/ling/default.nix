_:
let
  hostname = "lingmac";
in
{
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    wm.aerospace.enable = true;
    tools.hammerspoon.enable = false;
    tools.typeswitch.enable = false;
    tools.inputsourcepro.enable = true;
  };
}
