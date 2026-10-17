{
  pkgs,
  linuxPkgs,
  omp,
  gitConfig,
  msbConfig,
  msbHome,
  name,
  conf,
}:
let
  tools = with linuxPkgs; [
    bashInteractive
    coreutils
    ripgrep
    fd
    git
    gh
    jq
    curl
    mise
    bun
    omp
  ];

  entrypoint = pkgs.writeText "sb-entrypoint" ''
    export PATH="${pkgs.lib.makeBinPath tools}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    export GIT_SSL_CAINFO="$SSL_CERT_FILE"
    export GIT_CONFIG_GLOBAL="${gitConfig}"
    export XDG_DATA_HOME=/data/xdg/data
    export XDG_STATE_HOME=/data/xdg/state
    export XDG_CACHE_HOME=/data/xdg/cache
    # Linux stat 对 ext4 使用 ext2/ext3 的类型名；拒绝目录卷承载数据库
    if [[ "$(stat -f -c %T /data)" != ext2/ext3 ]]; then
      echo '/data 必须使用 disk 命名卷，请按 README 创建 --kind disk 的状态卷' >&2
      exit 1
    fi
    mkdir -p "$XDG_DATA_HOME/omp" "$XDG_STATE_HOME/omp" "$XDG_CACHE_HOME/omp"
    exec "$@"
  '';

  sb = pkgs.writeShellScriptBin name ''
    set -euo pipefail
    export MSB_CONFIG_PATH="${msbConfig}"
    export MSB_HOME="${msbHome}"

    usage() {
      cat <<'EOF'
    用法:
      ${name} up                       创建或启动 VM，自动经 sec-run 取得凭据
      ${name} exec [-t] [-w DIR] CMD…  在 VM 中运行命令
      ${name} shell                    进入交互 shell
      ${name} status                   查看状态
      ${name} inspect                  查看 JSON 规格与挂载
      ${name} volume …                 原生命名卷管理
      ${name} down                     停止 VM
      ${name} rm                       删除 VM，保留命名卷
    EOF
      exit "''${1:-0}"
    }

    [[ $# -gt 0 ]] || usage
    command="$1"
    shift
    case "$command" in
      up)
        if state=$(msb inspect ${name} --format json 2>/dev/null); then
          if ! ${pkgs.jq}/bin/jq -e '.status == "Running"' <<< "$state" >/dev/null; then
            sec-run msb start ${name}
          fi
        else
          sec-run msb create --name ${name} --conf ${conf}
        fi
        exit 0
        ;;
      exec) ;;
      shell) set -- -t bash "$@" ;;
      status) exec msb status ${name} "$@" ;;
      inspect) exec msb inspect ${name} --format json ;;
      volume) exec msb volume "$@" ;;
      down) exec msb stop ${name} "$@" ;;
      rm) exec msb rm --force ${name} "$@" ;;
      -h|--help|help) usage ;;
      *) usage 1 ;;
    esac

    terminal=(--stream)
    workdir=()
    while getopts ':tw:' option; do
      case "$option" in
        t) terminal=(-t) ;;
        w) workdir=(-w "$OPTARG") ;;
        *) usage 1 ;;
      esac
    done
    shift "$((OPTIND - 1))"
    [[ $# -gt 0 ]] || usage 1
    exec msb exec ${name} "''${terminal[@]}" "''${workdir[@]}" -- bash ${entrypoint} "$@"
  '';

  ompSb = pkgs.writeShellScriptBin "omp-sb" ''
    set -euo pipefail
    ${sb}/bin/${name} up >&2
    cwd=$(${sb}/bin/${name} inspect | ${pkgs.jq}/bin/jq -er --arg cwd "$(pwd -P)" '
      .active_config.mounts
      | map(select(.type == "Bind")
          | select(.host as $host | $cwd == $host or ($cwd | startswith($host + "/"))))
      | max_by(.host | length)
      | if . == null then error("当前目录未共享给 ${name}: \($cwd)")
        else . as $mount | $mount.guest + ($cwd | ltrimstr($mount.host)) end
    ')
    terminal=()
    if [[ -t 0 && -t 1 ]]; then terminal=(-t); fi
    exec ${sb}/bin/${name} exec "''${terminal[@]}" -w "$cwd" omp "$@"
  '';
in
pkgs.symlinkJoin {
  inherit name;
  paths = [
    sb
    ompSb
  ];
}
