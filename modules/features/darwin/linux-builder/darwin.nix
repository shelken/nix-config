# 让 nix 能把 Linux 构建交给本机的官方 darwin.linux-builder-vz（Apple Virtualization.framework）
#
# 背景：Determinate Native Linux Builder 因 FlakeHub 上 rosetta-guest 解析 404 不可用
# （DeterminateSystems/nix-src#730）。上游修复后，从主机 imports 里删掉本功能即可恢复。
#
# 排查结论（避免重复走弯路）：
#   - 404 始于 2026-10-23 15:30Z（上次成功 15:10Z），是服务端变化；与本机 Rosetta 无关：
#     macOS 27 升级会移除 Rosetta，装回后仍然 404
#   - determinate-nixd builder 传 --kernel/--initrd 也绕不过：daemon 仍会向 FlakeHub 解析 guest
#   - 修改 nix.custom.conf 后 daemon 不会重读，需要执行一次
#     sudo launchctl kickstart -k system/systems.determinate.nix-daemon
#   - guest 默认只有 1 核、约 2.9 GB 内存；调大要改 guest 配置，会失去缓存，需先有可用 builder
#
# 启停手动：
#   启动：linux-builder          （首次会要一次 sudo 密码，用来安装连接密钥；前台运行，Ctrl-C 优雅停机）
#   状态：linux-builder status   （运行中打印 PID 与启动时间）
#   停止：linux-builder stop     （向 vzvm 发 SIGINT，等 guest 优雅关机；原终端已关闭也能停）
#   重置：just builder-reset     （删掉 guest 磁盘，下次启动是空 store；运行中拒绝执行，先 stop）
# VM 没启动时，Linux 构建会因连不上 linux-builder 而失败。
#
# 可选功能：要用的主机在 imports 里加 self.modules.darwin.linux-builder
# 不用 nix-darwin 的 nix.linux-builder：它要求 nix.enable = true，与 Determinate 接管 Nix 冲突
{ ... }:
{
  flake.modules.darwin.linux-builder =
    { lib, pkgs, ... }:
    let
      # nixpkgs builder 镜像内置的公开 host key，只用于本机回环连接
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=";

      # create-builder 把密钥和磁盘镜像写在当前目录，固定到状态目录避免散落。
      # vzvm 进程的命令行里带 "$dir/vzvm.json"，stop/status 靠它定位 builder
      start = pkgs.writeShellApplication {
        name = "linux-builder";
        text = ''
          usage() {
            cat >&2 <<'EOF'
          用法：linux-builder [start|stop|status]

            （无参数） 前台启动 builder，Ctrl-C 优雅停机
            stop       停止运行中的 builder（发 SIGINT，等 guest 关机）
            status     显示 builder 是否在运行
            -h, --help 显示本用法
          EOF
          }

          dir="$HOME/.local/state/linux-builder"
          pattern="$dir/vzvm.json"
          grace=40

          running_pids() { pgrep -f "$pattern" || true; }

          do_start() {
            mkdir -p "$dir"
            cd "$dir"
            exec ${pkgs.darwin.linux-builder-vz}/bin/create-builder
          }

          do_status() {
            local pids pid
            pids="$(running_pids)"
            if [[ -z "$pids" ]]; then
              echo "linux-builder 未在运行"
              exit 1
            fi
            for pid in $pids; do
              echo "linux-builder 正在运行：PID $pid，启动于 $(ps -o lstart= -p "$pid" | sed -e 's/^ *//' -e 's/ *$//')"
            done
          }

          do_stop() {
            local pids pid deadline
            pids="$(running_pids)"
            if [[ -z "$pids" ]]; then
              echo "linux-builder 未在运行"
              exit 0
            fi
            for pid in $pids; do
              echo "向 vzvm（PID $pid）发 SIGINT，等 guest 优雅关机（最多 $grace 秒）"
              kill -INT "$pid"
            done
            deadline=$((SECONDS + grace))
            while (( SECONDS < deadline )); do
              if [[ -z "$(running_pids)" ]]; then
                echo "linux-builder 已停止"
                exit 0
              fi
              sleep 1
            done
            pids="$(running_pids)"
            echo "等了 $grace 秒仍未退出，还在运行：PID $pids" >&2
            echo "确认要强杀：kill $pids" >&2
            exit 1
          }

          case "''${1:-}" in
            "" | start)
              if [[ -n "''${2:-}" ]]; then
                usage
                exit 2
              fi
              do_start
              ;;
            status) do_status ;;
            stop) do_stop ;;
            -h | --help)
              usage
              exit 2
              ;;
            *)
              usage
              exit 2
              ;;
          esac
        '';
      };
    in
    {
      environment.systemPackages = [ start ];

      # 端口 31022 是 darwin.linux-builder-vz 的默认转发端口；密钥由它首次启动时生成并安装到 /etc/nix
      environment.etc."ssh/ssh_config.d/100-linux-builder.conf".text = ''
        Host linux-builder
          User builder
          Hostname localhost
          HostKeyAlias linux-builder
          Port 31022
          IdentityFile /etc/nix/builder_ed25519
      '';

      # 与 features/darwin/nix/_module.nix 里的 nix.custom.conf 合并（lines 类型按行拼接）
      environment.etc."nix/nix.custom.conf".text = lib.mkAfter ''
        builders = ssh-ng://builder@linux-builder aarch64-linux,x86_64-linux /etc/nix/builder_ed25519 4 - - - ${publicHostKey}
      '';
    };
}
