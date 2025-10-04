_: let
  hostname = "nano";
in {
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    tools.typeswitch.enable = true;
  };
}
