#!/usr/bin/env bash
# 由 _guest.nix 内嵌 guest/ 下四个模块，并在最前加载 guest-env.sh（路径与环境）。
set -euo pipefail

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

# 解析执行计划：JSON 有问题在占用槽位和锁之前就失败
parse_plan "$PLAN_JSON"

# 启动序列：槽位锁覆盖到布局结束，其他启动者在此排队
allocate_slot "$CTX_ID"

# 退出清理钩子放在 net_up 之前：网络配置中途失败也会拆掉已建的部分并归还槽位
cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM HUP
  release_slot "$CTX_ID" "$CURRENT_SLOT"
  exit "$exit_code"
}
trap cleanup EXIT INT TERM HUP

net_up "$CURRENT_SLOT"

prepare_declared_layout "$OTHER_CONTEXTS_COUNT"
release_slot_lock

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
  --bind "$SB_DATA_DIR" "$SB_DATA_DIR"
  --bind "$SB_MISE_LAYER" "$SB_MISE_LAYER"
  --ro-bind "$SB_CONFIG_MOUNT" "$SB_CONFIG_MOUNT"
  "${LAYOUT_ARGS[@]}"
)

IMPORTS_DIR="$CURRENT_CTX_DIR/imports"
for entry in "${PLAN_IMPORT_STAGES[@]}"; do
  IFS=$'\t' read -r stage dir <<< "$entry"
  [[ -n "$stage" ]] || continue
  dir="${dir/#\~/$HOME}"
  reject_reserved_target "$dir"
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

# bwrap 的 PID 1 要等命名空间里所有进程退出才返回：工具留下的后台守护（如 pi-intercom 的 broker 在最后一个客户端离开后再等 5 秒）
# 会拖住退出。主命令一退出就清场，先 TERM 让守护自己收尾，等到只剩 PID 1 与自己或超过 0.3 秒，再 KILL。
# kill -1 只作用于本上下文的 PID 命名空间，不影响其他上下文。INT 要留给子进程：trap 的处理函数不会被继承，
# 这样 Ctrl-C 杀掉子进程后 bash 仍会继续执行清场，而不是随信号退出
# shellcheck disable=SC2016  # 脚本在沙箱内的 bash 里展开，这里不能展开
CTX_SUPERVISOR='trap : INT
"$@"; rc=$?
kill -TERM -1 2>/dev/null
for _ in 1 2 3 4 5 6; do set -- /proc/[0-9]*; (($# <= 2)) && break; sleep 0.05; done
kill -KILL -1 2>/dev/null
exit "$rc"'

# 不使用 exec：保留 Bash 父进程等待子进程退出，EXIT cleanup trap 才会触发网络与资源释放
ip netns exec "$SLOT_NETNS" bwrap "${BWRAP_ARGS[@]}" -- bash -c "$CTX_SUPERVISOR" sb-ctx "$@"
