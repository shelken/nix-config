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
      write.enable = false;
      dev.enable = true;
      tools.enable = false;
      desktop.enable = true;
      homelab.enable = true;
      work.enable = true;
    };

    tools.main.enable = true;
    tools.rclone.enable = true;
    # tools.music.enable = true; # 音乐刮削相关
    # tools.image.enable = true; # 图片处理
    # tools.virts.enable = true; # 虚拟机
    # tools.others.enable = true; # 其他：altserver,备份
  };
  homebrew = {
    onActivation = {
      # autoUpdate = true;
      # 'zap': uninstalls all formulae(and related files) not listed in the generated Brewfile
      cleanup = "uninstall";
    };
  };
}
