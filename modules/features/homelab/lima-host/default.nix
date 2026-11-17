# lima-host：承载 Lima 节点的宿主（sakamoto、yuuko）。可选功能，宿主在 imports 里声明导入
# 系统侧：以 root 常驻的桥接网卡 socket_vmnet，供 Lima 实例经 socket 路径连接（非托管模式）；
# 托管模式要求二进制整条路径归 root 且组不可写，/nix/store 做不到，所以由 launchd 常驻。
# 宿主设 shelken.limaHost.*，Home Manager 部分经 osConfig 读取：实例声明、附加盘软链、自启动
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

  flake.modules.homeManager.lima-host =
    {
      config,
      lib,
      osConfig,
      pkgs,
      self,
      ...
    }:
    let
      inherit (osConfig.shelken.limaHost) node externalDisk;

      # limactl 由 Homebrew 安装（modules/features/virt/lima.nix），沿用它，不再引入第二份 Lima
      brewBin = "${osConfig.homebrew.prefix}/bin";

      # 节点只给数据，YAML 在宿主上用 darwin 的 pkgs 生成：直接用节点的 build 产物要 aarch64-linux 的 builder
      limaYaml =
        (pkgs.formats.yaml { }).generate "lima.yaml"
          self.nixosConfigurations.${node}.config.system.build.limaConfig;

      start = pkgs.writeShellApplication {
        name = "lima-host-start";
        text = ''
          log() {
            printf '%s lima-host: %s\n' "$(date '+%F %T')" "$*"
          }

          # 维护标记：重装、离线克隆时要保持停机，deploy 会重新加载 agent、StartOnMount 也会随时触发，
          # 只靠 bootout 挡不住
          if [ -e "$HOME/.lima/${node}/no-autostart" ]; then
            log '有维护标记 ~/.lima/${node}/no-autostart，跳过启动 ${node}'
            exit 0
          fi

          ${lib.optionalString (externalDisk != null) ''
            # 盘没挂时 macOS 不保留挂载点；残留的空目录与 /Volumes 同属一个设备，所以比设备号
            mounted() {
              local dev
              dev=$(/usr/bin/stat -f %d "$1" 2>/dev/null) || return 1
              [ "$dev" != "$(/usr/bin/stat -f %d /Volumes)" ]
            }
            if ! mounted ${lib.escapeShellArg externalDisk}; then
              log '外接盘 ${externalDisk} 未挂载，跳过启动 ${node}，挂载后由 StartOnMount 重试'
              exit 0
            fi
          ''}
          # 实例已在运行时 limactl 只提示并以 0 退出；否则它在后台起 hostagent、等到就绪后退出
          exec ${brewBin}/limactl start --tty=false ${node}
        '';
      };
    in
    {
      # lima.yaml 用 force 顶替手工放的旧文件（内容相同，不重要）；_disks 不用，它指向数据盘，首次部署前由人手动处理
      home.file = {
        ".lima/${node}/lima.yaml" = {
          source = limaYaml;
          force = true;
        };
      }
      // lib.optionalAttrs (externalDisk != null) {
        ".lima/_disks".source = config.lib.file.mkOutOfStoreSymlink "${externalDisk}/k8s/lima/_disks";
      };

      # 不设 KeepAlive：失败时不反复重试，盘挂载（StartOnMount）或下次登录再来。
      # 不用 limactl start --foreground 常驻：Home Manager 改 plist 会 bootout 这个 agent，
      # 常驻的 limactl 会随之退出并带走虚拟机。这里 limactl 把 hostagent 放进自己的进程组后退出，
      # AbandonProcessGroup 再保证 launchd 不会清理遗留进程，所以 agent 重载不会碰到运行中的虚拟机
      launchd.agents.lima-host = {
        enable = true;
        config = {
          Label = "space.ooooo.lima-host";
          ProgramArguments = [ "${start}/bin/lima-host-start" ];
          RunAtLoad = true;
          AbandonProcessGroup = true;
          EnvironmentVariables.PATH = "${brewBin}:/usr/bin:/bin:/usr/sbin:/sbin";
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/lima-host.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/lima-host.log";
        }
        // lib.optionalAttrs (externalDisk != null) { StartOnMount = true; };
      };
    };
}
