#!/usr/bin/env bash
# sb-launcher: 沙箱 Guest 内部执行上下文隔离调度器
# 职责：
# 组装 guest/plan.sh、netns.sh、registry.sh、layout.sh 四个内部模块（由 _guest.nix 内嵌），
# 协调槽位分配、网络隔离、布局规划与 bubblewrap 容器启动。执行计划只经 parse_plan 读取。
set -euo pipefail

export PATH="/data/xdg/data/mise/shims:${SB_GUEST_BIN_PATH:-/usr/local/bin:/usr/bin:/bin}"
export HOME="${HOME:-/root}"

# 1. 快速检查活跃上下文数 (--check-busy)
if [[ "${1:-}" == "--check-busy" ]]; then
  count_active_contexts
  exit 0
fi

if [[ $# -lt 3 ]]; then
  echo "[-] 错误: sb-launcher 参数不足。用法: sb-launcher <ctx_id> <plan_json> <cwd> [cmd...]" >&2
  exit 1
fi

CTX_ID="$1"
PLAN_JSON="$2"
CWD="$3"
shift 3

# 2. 解析执行计划：JSON 有问题在占用槽位和锁之前就失败
parse_plan "$PLAN_JSON"

# 3. 启动序列：槽位锁覆盖到布局结束，其他启动者在此排队
#    allocate_slot → net_up → prepare_declared_layout → release_slot_lock
allocate_slot "$CTX_ID"

# 4. 注册退出清理钩子：放在 net_up 之前，网络配置中途失败也会拆掉已建的部分并归还槽位
cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM HUP
  release_slot "$CTX_ID" "$CURRENT_SLOT"
  exit "$exit_code"
}
trap cleanup EXIT INT TERM HUP

net_up "$CURRENT_SLOT"

# 5. 准备声明配置布局与可写根
prepare_declared_layout "$OTHER_CONTEXTS_COUNT"
release_slot_lock

# 6. 构建 bubblewrap 隔离参数
BWRAP_ARGS=(
  --unshare-user --uid 1000 --gid 1000
  --unshare-ipc --unshare-pid --unshare-uts
  --ro-bind /usr /usr
  --ro-bind /bin /bin
  --ro-bind-try /lib /lib
  --ro-bind-try /lib64 /lib64
  --ro-bind /etc /etc
  --proc /proc
  --dev /dev
  --tmpfs /tmp
  --tmpfs /run
  --ro-bind /nix/store /nix/store
  --ro-bind-try /.msb/tls /.msb/tls
)

if [[ -d /data ]]; then
  BWRAP_ARGS+=(--bind /data /data)
  mkdir -p /data/xdg/data/omp /data/xdg/state/omp /data/xdg/cache/omp /data/xdg/config /data/mise /data/xdg/data/mise/shims
fi

# 宿主共用 mise 目录：挂载点、绑定模式与上下文环境由 _mise-layer.nix 经 _guest.nix 注入
[[ -d "$SB_MISE_LAYER" ]] && BWRAP_ARGS+=("$SB_MISE_BWRAP_BIND" "$SB_MISE_LAYER" "$SB_MISE_LAYER")
[[ -d /run/sandbox-config ]] && BWRAP_ARGS+=(--ro-bind /run/sandbox-config /run/sandbox-config)

BWRAP_ARGS+=("${LAYOUT_ARGS[@]}")

# 导入文件绑定
IMPORTS_DIR="$CURRENT_CTX_DIR/imports"
for entry in "${PLAN_IMPORT_STAGES[@]}"; do
  IFS=$'\t' read -r stage dir <<< "$entry"
  [[ -n "$stage" ]] || continue
  dir="${dir/#\~/$HOME}"
  case "$dir" in
    "$HOME" | / | /usr | /usr/* | /bin | /bin/* | /lib | /lib/* | /lib64 | /lib64/* | /etc | /etc/* | \
      /proc | /proc/* | /dev | /dev/* | /run | /run/* | /nix | /nix/* | /opt | /opt/* | /data | /data/* | \
      /.msb | /.msb/*)
      echo "[-] 错误: imports 的目标目录 $dir 是沙箱保留位置" >&2
      exit 1
      ;;
  esac
  if is_agent_layout_path "$dir"; then
    echo "[-] 错误: imports 的目标目录 $dir 是沙箱保留位置" >&2
    exit 1
  fi
  BWRAP_ARGS+=(--bind "$IMPORTS_DIR/$stage" "$dir")
done

BWRAP_ARGS+=(--bind "$PLAN_PROJECT_ROOT" "$PLAN_PROJECT_ROOT")

if [[ -n "$PLAN_GIT_COMMON_DIR" && "$PLAN_GIT_COMMON_DIR" != "$PLAN_PROJECT_ROOT" && "$PLAN_GIT_COMMON_DIR" != "$PLAN_PROJECT_ROOT"/* ]]; then
  [[ -e "$PLAN_GIT_COMMON_DIR" ]] && BWRAP_ARGS+=(--bind "$PLAN_GIT_COMMON_DIR" "$PLAN_GIT_COMMON_DIR")
fi

for entry in "${PLAN_PATHS[@]}"; do
  IFS=$'\t' read -r p ro <<< "$entry"
  if [[ -e "$p" ]]; then
    if [[ "$ro" == "true" ]]; then
      BWRAP_ARGS+=(--ro-bind "$p" "$p")
    else
      BWRAP_ARGS+=(--bind "$p" "$p")
    fi
  fi
done

if [[ -d "$CWD" ]]; then
  BWRAP_ARGS+=(--chdir "$CWD")
else
  BWRAP_ARGS+=(--chdir "$PLAN_PROJECT_ROOT")
fi

# 6. 加载环境规范并启动容器
export GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
export GIT_CONFIG_GLOBAL="${SB_GIT_CONFIG:-}"
if [[ -f /run/sandbox-config/current/guest-env.sh ]]; then
  # shellcheck source=/dev/null
  source /run/sandbox-config/current/guest-env.sh
fi

# 注意：不使用 exec，保留 Bash 父进程等待子进程退出，以确保 EXIT cleanup trap 触发网络与资源释放
ip netns exec "$SLOT_NETNS" bwrap "${BWRAP_ARGS[@]}" -- "$@"
