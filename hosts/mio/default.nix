{ self, ... }:
let
  hostname = "mio";
in
{
  imports = [
    self.modules.darwin.workstation
    self.modules.darwin.linux-builder
    self.modules.darwin.time-machine
  ];

  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    secrets.enable = true;
    wm.manager = "omniwm";
  };
  # 可选功能按需加入 imports，例如录屏 cap（OBS）

  homebrew = {
    onActivation = {
      autoUpdate = false;
      cleanup = "uninstall";
    };
  };
}
