_: let
  hostname = "sakamoto";
in {
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    wm = {
      aerospace.enable = true; # 平铺窗口管理
      iceBar.enable = true; # 菜单栏美化
    };
    suites = {
      desktop.enable = true; # 桌面：
    };
    write = {
      obsidian.enable = false;
    };
    dev = {
      container.enable = true;
      ide.enable = false;
      navicat.enable = false;
    };
    tools = {
      battery.enable = false;
      cap.enable = true;
      cherry-studio.enable = false;
      download.enable = false;
      gpt.enable = false;
      image.enable = false;
      music.enable = false;
      others.enable = false; # altstore
      rclone.enable = false;
      typeswitch.enable = true;
      virts.enable = true;
    };
    social = {
      feishu.enable = false;
      telegram.enable = false;
      wechat.enable = false;
    };
    homelab = {
      server.enable = true;
    };
    network = {
      fl-clash.enable = true;
    };
  };
  # homebrew = {
  #   onActivation = {
  #     # autoUpdate = true;
  #     # 'zap': uninstalls all formulae(and related files) not listed in the generated Brewfile
  #     cleanup = "uninstall";
  #   };
  # };
}
