_: let
  hostname = "mio";
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
      obsidian.enable = true;
    };
    dev = {
      container.enable = true;
      ide.enable = true;
      navicat.enable = true;
    };
    tools = {
      cap.enable = false;
      download.enable = true;
      gpt.enable = true;
      cherry-studio.enable = true;
      image.enable = true;
      music.enable = true;
      others.enable = true;
      rclone.enable = true;
      battery.enable = true;
    };
    social = {
      feishu.enable = false;
      telegram.enable = true;
      wechat.enable = true;
    };
    homelab = {
      client.enable = true;
    };
  };
  # homebrew = {
  #   onActivation = {
  #     cleanup = "uninstall";
  #   };
  # };
}
