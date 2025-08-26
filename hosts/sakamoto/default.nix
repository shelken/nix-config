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
      cap.enable = true;
      download.enable = false;
      gpt.enable = false;
      cherry-studio.enable = false;
      image.enable = false;
      music.enable = false;
      others.enable = false; # altstore
      rclone.enable = false;
      battery.enable = false;
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
  };
  # homebrew = {
  #   onActivation = {
  #     # autoUpdate = true;
  #     # 'zap': uninstalls all formulae(and related files) not listed in the generated Brewfile
  #     cleanup = "uninstall";
  #   };
  # };
}
