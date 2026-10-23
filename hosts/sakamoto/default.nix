{ self, ... }:
let
  hostname = "sakamoto";
in
{
  imports = with self.modules.darwin; [
    desktop
    homelab
    virts
  ];

  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    secrets.enable = true;
  };
  # homebrew = {
  #   onActivation = {
  #     # autoUpdate = true;
  #     # 'zap': uninstalls all formulae(and related files) not listed in the generated Brewfile
  #     cleanup = "uninstall";
  #   };
  # };
}
