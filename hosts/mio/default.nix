{ self, ... }:
let
  hostname = "mio";
in
{
  imports = [
    self.modules.darwin.workstation
    self.modules.darwin.time-machine
    self.modules.darwin.dnscontrol
    self.modules.darwin.openwrt
  ];

  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken.secrets.enable = true;

  homebrew = {
    onActivation = {
      autoUpdate = false;
      cleanup = "uninstall";
    };
  };
}
