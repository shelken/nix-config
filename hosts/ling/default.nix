_: let
  hostname = "lingmac";
in {
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    wm.skhd.enable = false;
    wm.yabai.enable = false;
  };
}
