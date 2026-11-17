{ self, ... }:
let
  hostname = "yuuko";
in
{
  # agent 执行节点：只要 ai 运行时与承载 Lima 节点所需的 lima-host，工作站专属能力不导入（ADR 0004、0008）
  imports = with self.modules.darwin; [
    desktop
    homelab
    ai
    lima-host
  ];

  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;
  shelken = {
    secrets.enable = true;
    limaHost.node = "yuuko-k8s";
  };
}
