_: let
  hostname = "nano";
in {
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    wm.skhd.enable = true;
    wm.yabai.enable = true;
  };
}
