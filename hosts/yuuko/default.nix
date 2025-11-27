_:
let
  hostname = "yuuko";
in
{
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    wm.aerospace.enable = true;
    tools.typeswitch.enable = true;
    suites.desktop.enable = true;
    dev.container.enable = true;
    network.fl-clash.enable = true;
  };
}
