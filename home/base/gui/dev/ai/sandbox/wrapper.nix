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

  growVolume = pkgs.writeShellScript "sb-volume-grow" ''
    set -euo pipefail
    if [[ $# != 1 || "$1" == -h || "$1" == --help ]]; then
      echo '用法: ${name} volume grow SIZE，例如 32G'
      [[ $# == 1 ]] && exit 0
      exit 2
    fi
    size="$1"
    state=$(msb inspect ${name} --format json)
    status=$(${pkgs.jq}/bin/jq -er '.status | select(. == "Running" or . == "Stopped")' <<< "$state")
    volume=$(${pkgs.jq}/bin/jq -er '
      [(if .status == "Running" then .active_config else .config end).mounts[]
        | select(.type == "Named" and .guest == "/data")]
      | if length == 1 then .[0].name else error("/data 必须挂载一个命名卷") end
    ' <<< "$state")
    info=$(msb volume list --format json | ${pkgs.jq}/bin/jq -ec --arg name "$volume" '
      .[] | select(.name == $name)
      | if .kind == "disk" and .disk_format == "raw" and .disk_fstype == "ext4"
        then . else error("扩容只支持 raw ext4 磁盘卷") end
    ')
    old_capacity=$(${pkgs.jq}/bin/jq -r '.capacity_bytes' <<< "$info")
    source_disk="$MSB_HOME/volumes/$volume/disk.raw"
    [[ -f "$source_disk" ]] || { echo "找不到卷镜像: $source_disk" >&2; exit 1; }
    temporary="${name}-grow-$$"
    helper="grow-$$"
    temporary_disk="$MSB_HOME/volumes/$temporary/disk.raw"
    phase=prepared

    cleanup() {
      result=$?
      trap - EXIT INT TERM
      if msb inspect "$helper" --format json >/dev/null 2>&1; then
        if ! msb rm --force "$helper" >/dev/null; then
          echo "无法清理迁移 VM ''${helper}，保留临时卷 $temporary" >&2
          exit 1
        fi
      fi
      if [[ "$phase" == replacing ]]; then
        echo "扩容未完成，已校验的数据保留在卷 ''${temporary}；${name} 保持停止" >&2
        exit 1
      fi
      if ! msb volume rm "$temporary" >/dev/null; then
        result=1
      fi
      if [[ "$status" == Running && "$phase" != prepared ]]; then
        if ! sec-run msb start ${name}; then
          echo '卷数据已保留，VM 启动失败' >&2
          result=1
        fi
      fi
      if [[ "$result" == 0 && "$phase" == complete ]]; then
        echo "卷 $volume 已扩容到 $size"
      fi
      exit "$result"
    }

    msb volume create "$temporary" --kind disk --size "$size" --quiet >/dev/null
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    new_capacity=$(msb volume list --format json | ${pkgs.jq}/bin/jq -er --arg name "$temporary" '
      .[] | select(.name == $name) | .capacity_bytes
    ')
    if (( new_capacity == old_capacity )); then
      echo "卷 $volume 已是 ''${size}，无需扩容"
      exit 0
    fi
    if (( new_capacity < old_capacity )); then
      echo '目标容量必须大于当前容量，不支持缩容' >&2
      exit 1
    fi

    phase=copying
    if [[ "$status" == Running ]]; then msb stop ${name}; fi
    msb run --name "$helper" --pull never --no-stdin \
      --mount-named "$volume:/old:kind=disk,size=$((old_capacity / 1024 / 1024))M,ro" \
      --mount-named "$temporary:/new:kind=disk,size=$size" \
      ubuntu -- bash -euo pipefail -c '
        cp -a /old/. /new/
        tar --acls --xattrs --numeric-owner -C /old -cf - . |
          tar --acls --xattrs --numeric-owner -C /new -df -
        sync
      '
    msb rm --force "$helper" >/dev/null

    # 容量记录交给原生 API 更新，避免直接修改 msb 数据库。
    phase=replacing
    msb volume rm "$volume" >/dev/null
    msb volume create "$volume" --kind disk --size "$size" --quiet >/dev/null
    # 两个卷目录同属 MSB_HOME；保留临时硬链接，替换失败时仍有完整数据。
    ${pkgs.coreutils}/bin/ln -f "$temporary_disk" "$source_disk"
    phase=complete
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
      ${name} volume grow SIZE         扩容 /data 磁盘卷，保留卷名并恢复原运行状态
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
      volume)
        if [[ "''${1:-}" == grow ]]; then
          shift
          exec ${growVolume} "$@"
        fi
        exec msb volume "$@"
        ;;
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
