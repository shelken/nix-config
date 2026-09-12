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

    neovim = {
      enable = true;
      minimal = true;
    };

    wm.aerospace.enable = true;
  };
}
