{ self, ... }:
let
  hostname = "sakamoto";
in
{
  imports = with self.modules.darwin; [
    desktop
    homelab
    virts
    lima-host
  ];

  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    secrets.enable = true;
    limaHost = {
      node = "sakamoto-k8s";
      # Lima 的附加盘（Longhorn 数据盘）在外接盘上
      externalDisk = "/Volumes/sakamoto-data";
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
