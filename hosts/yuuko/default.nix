_: let
  hostname = "yuuko";
in {
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    wm = {
      aerospace.enable = true;
      iceBar.enable = true;
    };
    suites = {
      write.enable = true;
      dev.enable = true;
      tools.enable = true;
      desktop.enable = true;
      homelab.enable = true;
      work.enable = true;
    };

    tools.music.enable = true;
    tools.image.enable = true;
    tools.others.enable = true;

    social.personal.enable = true;
  };
  homebrew = {
    onActivation = {
      # autoUpdate = true;
      # 'zap': uninstalls all formulae(and related files) not listed in the generated Brewfile
      cleanup = "zap";
    };
  };
}
