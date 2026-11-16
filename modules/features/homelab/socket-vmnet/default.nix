# socket-vmnet：以 root 常驻的桥接网卡 socket_vmnet，供 Lima 实例经 socket 路径连接（非托管模式）
# 可选功能，只有承载 Lima 节点的主机（sakamoto、yuuko）导入
# 托管模式要求二进制整条路径归 root 且组不可写，/nix/store 做不到，所以由 launchd 常驻
{ ... }:
{
  flake.modules.darwin.socket-vmnet =
    {
      config,
      pkgs,
      lib,
      myvars,
      ...
    }:
    let
      cfg = config.shelken.socketVmnet;
      # 与上游 launchd/io.github.lima-vm.socket_vmnet.bridged.en0.plist 的命名一致
      name = "socket_vmnet.bridged.${cfg.interface}";
    in
    {
      options.shelken.socketVmnet.interface = lib.mkOption {
        type = lib.types.str;
        default = myvars.socketVmnet.interface;
        description = "桥接到的宿主网卡；改它时 hosts/k8s/lima.nix 的 socket 路径要同步";
      };

      config.launchd.daemons.socket-vmnet.serviceConfig = {
        Label = "io.github.lima-vm.${name}";
        ProgramArguments = [
          "${pkgs.socket-vmnet}/bin/socket_vmnet"
          "--vmnet-mode=bridged"
          "--vmnet-interface=${cfg.interface}"
          (myvars.socketVmnet.socketFor cfg.interface)
        ];
        UserName = "root";
        RunAtLoad = true;
        KeepAlive = true;
        # 日志放平，launchd 不会替 /var/log 下的子目录建目录
        StandardOutPath = "/var/log/${name}.stdout";
        StandardErrorPath = "/var/log/${name}.stderr";
        # 避免资源限制拖慢网络转发
        ProcessType = "Interactive";
      };
    };
}
