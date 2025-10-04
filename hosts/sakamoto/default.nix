_: let
  hostname = "sakamoto";
in {
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    # window manager
    wm.aerospace.enable = true; # 平铺窗口管理

    # suites
    suites.desktop.enable = true;

    # development
    dev.container.enable = true; # docker

    # tools
    tools.typeswitch.enable = true;
    tools.virts.enable = true;

    # homelab
    homelab.server.enable = true;

    # network
    network.fl-clash.enable = true;
  };
  # homebrew = {
  #   onActivation = {
  #     # autoUpdate = true;
  #     # 'zap': uninstalls all formulae(and related files) not listed in the generated Brewfile
  #     cleanup = "uninstall";
  #   };
  # };
}
