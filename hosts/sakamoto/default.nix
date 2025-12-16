_:
let
  hostname = "sakamoto";
in
{
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    dev.container.enable = true; # docker

    homelab.server.enable = true;

    network.fl-clash.enable = true;

    suites.desktop.enable = true;

    tools.typeswitch.enable = true;
    tools.virts.enable = true;

    wm.aerospace.enable = true;
  };
  # homebrew = {
  #   onActivation = {
  #     # autoUpdate = true;
  #     # 'zap': uninstalls all formulae(and related files) not listed in the generated Brewfile
  #     cleanup = "uninstall";
  #   };
  # };
}
