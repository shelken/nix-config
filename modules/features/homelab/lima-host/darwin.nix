# lima-host：承载 Lima 节点的宿主（sakamoto、yuuko）。可选功能，宿主在 imports 里声明导入
# 系统侧：以 root 常驻的桥接网卡 socket_vmnet，供 Lima 实例经 socket 路径连接（非托管模式）；
# 托管模式要求二进制整条路径归 root 且组不可写，/nix/store 做不到，所以由 launchd 常驻。
# 宿主设 shelken.limaHost.*，Home Manager 部分（./home.nix）经 osConfig 读取：实例声明、附加盘软链、自启动
{ ... }:
{
  flake.modules.darwin.lima-host =
    {
      lib,
      pkgs,
      myvars,
      ...
    }:
    let
      inherit (myvars.socketVmnet) interface socket;
      # 与上游 launchd/io.github.lima-vm.socket_vmnet.bridged.en0.plist 的命名一致
      name = "socket_vmnet.bridged.${interface}";
    in
    {
      options.shelken.limaHost = {
        node = lib.mkOption {
          type = lib.types.str;
          example = "sakamoto-k8s";
          description = "宿主承载的 Lima 节点：nixosConfigurations 里的名字，也是 Lima 的实例名";
        };
        externalDisk = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/Volumes/sakamoto-data";
          description = ''
            实例依赖的外接盘挂载点。设置后：自启动前先检查它已挂载，
            ~/.lima/_disks 指向盘上的 k8s/lima/_disks
          '';
        };
      };

      config.launchd.daemons.socket-vmnet.serviceConfig = {
        Label = "io.github.lima-vm.${name}";
        ProgramArguments = [
          "${pkgs.socket-vmnet}/bin/socket_vmnet"
          "--vmnet-mode=bridged"
          "--vmnet-interface=${interface}"
          socket
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
