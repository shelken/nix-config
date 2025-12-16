_:
let
  hostname = "yuuko";
in
{
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    dev.container.enable = true;

    homelab.server.enable = true;

    network.fl-clash.enable = true;

    suites.desktop.enable = true;

    tools.typeswitch.enable = true;

    wm.aerospace.enable = true;
  };
}
