# sb CLI: 一个机器一个 wrapper, 管理单个常驻沙箱 VM
# 多 agent 进程 = 多次 sb exec / sb ssh 接入同一个 VM
#
# 机器定义完全采用原生 msb YAML (machines/<name>.yaml)，Nix 不动态渲染配置。
# Nix 仅用于声明依赖的 Linux 工具链 store 路径，并通过 entrypoint 提供给沙箱。
{
  pkgs, # native (aarch64-darwin)
  linuxPkgs,
  name,
  machine,
  # agent CLI 来自 llm-agents.nix 上游 (aarch64-linux, 缓存替换), ADR 0003;
  # 仅用于拼 entrypoint PATH, 本体走宿主 /nix/store 挂载
  omp,
}:
let
  lib = pkgs.lib;

  tools = (if builtins.isFunction machine.tools then machine.tools linuxPkgs else machine.tools) ++ [ omp ];

  # VM 内入口: 设置 nix 工具 PATH 与证书再 exec
  # 纯文本文件, 无需可执行位; 遵循 issue 1607 定稿约束: 不用 msb --env (会干扰 secret 机制)
  entrypoint = pkgs.writeText "sb-entrypoint" ''
    export PATH="${lib.makeBinPath tools}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    export SSL_CERT_FILE="${linuxPkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

    # XDG 状态与数据库分流：SQLite 数据库、会话天然写入持久卷，配置目录保持只读
    export XDG_DATA_HOME=/data/xdg/data
    export XDG_STATE_HOME=/data/xdg/state
    export XDG_CACHE_HOME=/data/xdg/cache
    mkdir -p "$XDG_DATA_HOME/omp" "$XDG_STATE_HOME/omp" "$XDG_CACHE_HOME/omp"

    # 插件首次自动原生构建：缺失时使用自带 Linux bun 在持久卷内执行安装
    mkdir -p /data/plugins
    ln -sfn /data/plugins "$XDG_DATA_HOME/omp/plugins"
    if [ -f /data/plugins/package.json ] && [ ! -d /data/plugins/node_modules ]; then
      (cd /data/plugins && bun install --silent) || true
    fi

    exec "''$@"
  '';


  conf = machine.conf;
  sbName = "sb-${name}";
  entrypointGuest = "/nix/store/${baseNameOf entrypoint}";
in
pkgs.writeShellScriptBin "sb-${name}" ''
  # msb 由 mise 在宿主机管理 (0.7.7+), wrapper 继承环境 PATH
  set -euo pipefail

  SB_NAME="${sbName}"
  CONF="${conf}"
  ENTRYPOINT="${entrypointGuest}"

  usage() {
    cat <<EOF
Usage: sb-${name} <command> [args...]

管理常驻 agent 沙箱 $SB_NAME (多 agent 共享, 每次 exec/ssh 即一个接入)

Commands:
  up                 创建(如不存在)并启动 VM
  exec [-t] <cmd> ...  在 VM 内以 nix 工具 PATH 执行命令 (-t 分配 PTY, TUI 用)
  shell              交互 shell
  ssh                底层 SSH 运维通道
  serve              暴露 SSH server 127.0.0.1:2222 (前台), 首次需 msb ssh authorize:
                     msb ssh authorize --file ~/.ssh/id_ed25519.pub
                     ssh -p 2222 root@127.0.0.1
  status             查看状态
  down               停止 (磁盘保留)
  rm                 销毁 VM
EOF
    exit "''${1:-0}"
  }

  cmd_up() {
    if msb inspect "$SB_NAME" &>/dev/null; then
      if msb status "$SB_NAME" 2>/dev/null | grep -q "running"; then
        echo "$SB_NAME already running."
      else
        msb start "$SB_NAME"
        echo "$SB_NAME started."
      fi
    else
      msb create --name "$SB_NAME" --conf "$CONF"
      echo "$SB_NAME created and booted."
    fi
  }
  # -t 透传给 msb exec (TUI 需要 PTY), 其余参数原样执行
  cmd_exec() {
    local tty_args=()
    if [ "''${1:-}" = "-t" ]; then tty_args=(-t); shift; fi
    exec msb exec "$SB_NAME" "''${tty_args[@]}" -- bash "$ENTRYPOINT" "$@"
  }

  cmd_shell() {
    exec msb exec "$SB_NAME" -t -- bash "$ENTRYPOINT" bash
  }

  [ $# -lt 1 ] && usage 1
  command="$1"; shift

  case "$command" in
    up) cmd_up ;;
    exec)
      [ $# -lt 1 ] && { echo "Usage: sb-${name} exec <cmd> [args...]" >&2; exit 1; }
      cmd_exec "$@"
      ;;
    shell) cmd_shell ;;
    ssh)
      exec msb ssh "$SB_NAME" "''$@"
      ;;
    serve) exec msb ssh serve "$SB_NAME" "$@" ;;
    status) exec msb status "$SB_NAME" "$@" ;;
    down) exec msb stop "$SB_NAME" "$@" ;;
    rm) msb stop "$SB_NAME" 2>/dev/null || true; exec msb rm "$SB_NAME" "$@" ;;
    -h|--help|help) usage 0 ;;
    *) echo "Unknown command: $command" >&2; usage 1 ;;
  esac
''
