{ ... }:
{
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

      # limactl 由 Homebrew 安装（modules/features/dev/lima.nix），沿用它，不再引入第二份 Lima
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
      home.file = {
        ".lima/${node}/lima.yaml".source = limaYaml;
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
