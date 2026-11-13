{ self, ... }:
let
  hostname = "yuuko";
in
{
  # agent 执行节点：只要 ai 运行时，工作站专属能力不导入（ADR 0004、0008）
  imports = with self.modules.darwin; [
    desktop
    homelab
    ai
  ];

  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    secrets.enable = true;
  };
}
