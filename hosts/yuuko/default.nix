_: let
  hostname = "yuuko";
in {
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  imports = [
    ./apps.nix
  ];
  shelken.wm.aerospace.enable = true;
}
