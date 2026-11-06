#!/usr/bin/env bash
# sb-launcher: 沙箱 Guest 内部执行上下文隔离调度器
# 职责：
# 组装 guest/netns.sh、guest/registry.sh、guest/layout.sh 三个内部模块，
# 协调槽位分配、网络隔离、布局规划与 bubblewrap 容器启动。
set -euo pipefail

export PATH="/data/xdg/data/mise/shims:${SB_GUEST_BIN_PATH:-/usr/local/bin:/usr/bin:/bin}"
export HOME="${HOME:-/root}"
# 如果是在独立脚本环境下运行且子模块未内嵌，则动态加载
if ! declare -f allocate_slot >/dev/null 2>&1; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/guest/netns.sh"
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/guest/registry.sh"
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/guest/layout.sh"
fi

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

# 2. 槽位分配与网络初始化（内部自动清理死上下文并发布元数据）
allocate_slot "$CTX_ID" "$PLAN_JSON"

# 3. 注册退出清理钩子（无论是正规退出还是信号中断，统一归还槽位与拆卸网络）
cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM HUP
  release_slot "$CTX_ID" "$CURRENT_SLOT"
  exit "$exit_code"
}
trap cleanup EXIT INT TERM HUP

# 4. 准备声明配置布局与可写根
prepare_declared_layout "$OTHER_CONTEXTS_COUNT"
release_slot_lock

# 5. 构建 bubblewrap 隔离参数
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

# 宿主共用 mise 目录：上下文可写，项目工具按需安装并跨 VM 重建保留
[[ -d /opt/sandbox-mise ]] && BWRAP_ARGS+=(--bind /opt/sandbox-mise /opt/sandbox-mise)
[[ -d /run/sandbox-config ]] && BWRAP_ARGS+=(--ro-bind /run/sandbox-config /run/sandbox-config)

BWRAP_ARGS+=("${LAYOUT_ARGS[@]}")

# 导入文件绑定
IMPORTS_DIR="$CURRENT_CTX_DIR/imports"
while IFS=$'\t' read -r stage dir; do
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
done < <(jq -r '[.imports[]? | [.stage, .dir]] | unique[] | @tsv' <<< "$PLAN_JSON")

PROJECT_ROOT="$(jq -r '.project_root' <<< "$PLAN_JSON")"
GIT_COMMON_DIR="$(jq -r '.git_common_dir // empty' <<< "$PLAN_JSON")"

BWRAP_ARGS+=(--bind "$PROJECT_ROOT" "$PROJECT_ROOT")

if [[ -n "$GIT_COMMON_DIR" && "$GIT_COMMON_DIR" != "$PROJECT_ROOT" && "$GIT_COMMON_DIR" != "$PROJECT_ROOT"/* ]]; then
  [[ -e "$GIT_COMMON_DIR" ]] && BWRAP_ARGS+=(--bind "$GIT_COMMON_DIR" "$GIT_COMMON_DIR")
fi

while IFS= read -r item; do
  [[ -n "$item" ]] || continue
  p="$(jq -r .path <<< "$item")"
  ro="$(jq -r '.readonly // false' <<< "$item")"
  if [[ -e "$p" ]]; then
    if [[ "$ro" == "true" ]]; then
      BWRAP_ARGS+=(--ro-bind "$p" "$p")
    else
      BWRAP_ARGS+=(--bind "$p" "$p")
    fi
  fi
done < <(jq -c '.paths[]? // empty' <<< "$PLAN_JSON")

if [[ -d "$CWD" ]]; then
  BWRAP_ARGS+=(--chdir "$CWD")
else
  BWRAP_ARGS+=(--chdir "$PROJECT_ROOT")
fi

# 6. 加载环境规范并启动容器
export GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
export GIT_CONFIG_GLOBAL="${SB_GIT_CONFIG:-}"
if [[ -f /run/sandbox-config/current/guest-env.sh ]]; then
  # shellcheck source=/dev/null
  source /run/sandbox-config/current/guest-env.sh
fi
# 不用 MISE_OFFLINE：它连安装下载也禁止。PREFER_OFFLINE 只在本地已有版本时不联网，
# 已装的 latest（如 minio/mc，版本列表约 14 MB，超过 mise 超时）不再每次启动白等。
# 写在这里而不是 guest-env.sh：sb sync 也 source 它，sync 必须联网解析
export MISE_PREFER_OFFLINE=1

# 注意：不使用 exec，保留 Bash 父进程等待子进程退出，以确保 EXIT cleanup trap 触发网络与资源释放
ip netns exec "$SLOT_NETNS" bwrap "${BWRAP_ARGS[@]}" -- "$@"
