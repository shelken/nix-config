_:
let
  hostname = "mio";
in
{
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    # window manager
    wm.aerospace.enable = true;
    tools.hammerspoon.enable = true;
    wm.iceBar.enable = false; # 菜单栏美化

    # suites
    suites.desktop.enable = true;

    # write
    write.obsidian.enable = true;

    # development
    dev.container.enable = true; # docker/orbstack
    dev.ide.enable = true;
    dev.navicat.enable = true;

    # tools
    tools.battery.enable = true;
    tools.cap.enable = false; # 录屏obs
    tools.cherry-studio.enable = true;
    tools.download.enable = true;
    tools.gpt.enable = true;
    tools.image.enable = true;
    tools.music.enable = true;
    tools.others.enable = true;
    tools.rclone.enable = true;
    tools.typeswitch.enable = false; # 用 Hammerspoon
    tools.virts.enable = false; # utm parallel

    # social
    social.feishu.enable = false;
    social.telegram.enable = true;
    social.wechat.enable = true;

    # homelab
    homelab.client.enable = true;

    # network
    network.fl-clash.enable = true;
  };
  homebrew = {
    onActivation = {
      autoUpdate = false;
      cleanup = "uninstall";
    };
  };
}
