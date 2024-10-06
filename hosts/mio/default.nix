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
      write.enable = true; # 写作
      dev.enable = true; # 开发
      tools.enable = true; # 工具
      desktop.enable = true; # 桌面：
      homelab.enable = true; # homelab
      work.enable = true; # 工作
    };

    # tools.music.enable = true; # 音乐刮削相关
    # tools.image.enable = true; # 图片处理
    # tools.virts.enable = true; # 虚拟机
    # tools.others.enable = true; # 其他：altserver,备份

    social.personal.enable = true; # 个人相关：通信telegram
  };
}
