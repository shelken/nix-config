#!/usr/bin/env bash
# sb-launcher: 沙箱 Guest 内部执行上下文隔离器
# 职责：
# 1. 槽位锁分配、死上下文清理与元数据发布 (meta.json)
# 2. 独立网络命名空间配置 (netns, veth, iptables 规则链与私网拦截)
# 3. 声明配置只读覆盖与数据盘可写根布局生成 (bubblewrap layout)
# 4. 执行上下文构建与 bubblewrap 隔离启动
set -euo pipefail

export PATH="/data/xdg/data/mise/shims:${SB_GUEST_BIN_PATH:-/usr/local/bin:/usr/bin:/bin}"
export HOME="${HOME:-/root}"

CONTEXTS_DIR="/run/sandbox/contexts"
MAX_SLOTS=64
STARTUP_GRACE_SECS=120
SLOT_LOCK="$CONTEXTS_DIR/.slot.lock"

acquire_slot_lock() {
  mkdir -p "$CONTEXTS_DIR"
  exec 9>>"$SLOT_LOCK"
  flock -x -w 30 9
}

release_slot_lock() {
  flock -u 9 2>/dev/null || true
  exec 9>&-
}

is_starting() {
  local ctx_dir="$1" st
  [[ -f "$ctx_dir/starting" ]] || return 1
  st="$(stat -c %Y "$ctx_dir/starting" 2>/dev/null || echo 0)"
  (( $(date +%s) - st < STARTUP_GRACE_SECS ))
}

sweep_dead_contexts() {
  [[ -d "$CONTEXTS_DIR" ]] || return 0
  for ctx_dir in "$CONTEXTS_DIR"/*; do
    [[ -d "$ctx_dir" ]] || continue
    local meta="$ctx_dir/meta.json"
    if [[ ! -f "$meta" ]]; then
      if is_starting "$ctx_dir"; then
        continue
      fi
      rm -rf "$ctx_dir"
      continue
    fi
    local pid slot veth netns chain
    pid="$(jq -r '.pid // empty' "$meta" 2>/dev/null || true)"
    slot="$(jq -r '.slot // empty' "$meta" 2>/dev/null || true)"
    veth="$(jq -r '.veth_host // empty' "$meta" 2>/dev/null || true)"
    netns="$(jq -r '.netns // empty' "$meta" 2>/dev/null || true)"
    chain="$(jq -r '.chain // empty' "$meta" 2>/dev/null || true)"
    if [[ -z "$pid" || ! -d "/proc/$pid" ]]; then
      if [[ -n "$chain" ]]; then
        iptables -D FORWARD -s "10.200.$((slot / 64)).$(( (slot % 64) * 4 + 2 ))" -j "$chain" 2>/dev/null || true
        iptables -F "$chain" 2>/dev/null || true
        iptables -X "$chain" 2>/dev/null || true
      fi
      [[ -n "$veth" ]] && ip link del "$veth" 2>/dev/null || true
      [[ -n "$netns" ]] && ip netns del "$netns" 2>/dev/null || true
      rm -rf "$ctx_dir"
    fi
  done
}

declare -A AGENT_ROOTS=()
LAYOUT_ARGS=()
MOUNT_POINTS=()

declared_dst() {
  local t="$1"
  if [[ "$t" == .config/* ]]; then
    printf '%s/%s\n' "${XDG_CONFIG_HOME:-/data/xdg/config}" "${t#.config/}"
  else
    printf '%s/%s\n' "$HOME" "$t"
  fi
}

backing_of() {
  local path="$1" root
  for root in "${!AGENT_ROOTS[@]}"; do
    if [[ "$path" == "$root" || "$path" == "$root/"* ]]; then
      printf '%s%s\n' "${AGENT_ROOTS[$root]}" "${path#"$root"}"
      return 0
    fi
  done
  printf '%s\n' "$path"
}

mount_root_of() {
  local path="$1" root
  for root in "${!AGENT_ROOTS[@]}"; do
    if [[ "$path" == "$root" || "$path" == "$root/"* ]]; then
      printf '%s\n' "$root"
      return 0
    fi
  done
  if [[ "$path" == "${XDG_CONFIG_HOME:-/data/xdg/config}"* ]]; then
    printf '%s\n' "${XDG_CONFIG_HOME:-/data/xdg/config}"
    return 0
  fi
  return 1
}

is_empty_placeholder() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  local entries
  entries="$(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1 || true)"
  [[ -z "$entries" ]]
}

resolve_conflict() {
  local path="$1" want="$2" others="$3"
  if [[ "$others" -gt 0 ]]; then
    echo "[-] 错误: 数据盘路径冲突：$path（期望 $want，但存在不同类型的项），有其他上下文在运行，不自动覆盖以免破坏它们" >&2
    exit 1
  fi
  if is_empty_placeholder "$path"; then
    rm -rf "$path"
    return 0
  fi
  echo "[-] 错误: 数据盘路径冲突：$path（期望 $want，但存在非空项），清空该路径后重试" >&2
  exit 1
}

is_agent_layout_path() {
  local target="$1" p
  for p in "${MOUNT_POINTS[@]}"; do
    [[ "$target" == "$p" || "$target" == "$p/"* ]] && return 0
  done
  for p in "${!AGENT_ROOTS[@]}"; do
    [[ "$target" == "$p" || "$target" == "$p/"* ]] && return 0
  done
  return 1
}

require_published() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "[-] 错误: 沙箱发布目录不完整（缺少 $file），重新发布配置后重试：just hm" >&2
    exit 1
  fi
}

# 声明配置布局规划（启动锁内调用）
prepare_declared_layout() {
  local others="$1" cfg list roots_file rel t dst src want root p a
  local -a ancestors=() binds=() uppers=()
  [[ -e /run/sandbox-config/current ]] || return 0
  cfg="$(readlink -f /run/sandbox-config/current)"
  list="$cfg/declared-paths"
  roots_file="$cfg/writable-roots"
  require_published "$list"
  require_published "$roots_file"

  LAYOUT_ARGS+=(--tmpfs "$HOME")
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    root="$HOME/$rel"
    AGENT_ROOTS["$root"]="/data/home/$rel"
    mkdir -p "${AGENT_ROOTS[$root]}"
    p="${root%/*}"
    while [[ "$p" == "$HOME/"* ]]; do
      uppers+=("$p")
      p="${p%/*}"
    done
  done < "$roots_file"

  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    MOUNT_POINTS+=("$p")
    LAYOUT_ARGS+=(--dir "$p" --tmpfs "$p")
  done < <(printf '%s\n' "${uppers[@]}" | LC_ALL=C sort -u)

  for root in "${!AGENT_ROOTS[@]}"; do
    LAYOUT_ARGS+=(--bind "${AGENT_ROOTS[$root]}" "$root")
  done

  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    src="$cfg/$t"
    if [[ ! -e "$src" ]]; then
      echo "[-] 错误: 声明配置缺失：$src（发布目录不完整，重新发布后重试）" >&2
      exit 1
    fi
    dst="$(declared_dst "$t")"
    if ! root="$(mount_root_of "$dst")"; then
      echo "[-] 错误: 声明配置 $t 不在任何可写根或 .config/ 下（重新发布配置后重试：just hm）" >&2
      exit 1
    fi
    p="$(dirname "$dst")"
    while [[ "$p" != "$root" && "$p" != / ]]; do
      ancestors+=("$p")
      p="$(dirname "$p")"
    done
    if [[ -d "$src" ]]; then want="目录"; else want="文件"; fi
    a="$(backing_of "$dst")"
    if [[ -e "$a" || -L "$a" ]]; then
      if [[ -L "$a" ]] || { [[ "$want" == "目录" ]] && [[ ! -d "$a" ]]; } || { [[ "$want" == "文件" ]] && [[ -d "$a" ]]; }; then
        resolve_conflict "$a" "$want" "$others"
      fi
    fi
    binds+=(--ro-bind "$src" "$dst")
  done < "$list"

  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    a="$(backing_of "$p")"
    if [[ -L "$a" ]] || { [[ -e "$a" ]] && [[ ! -d "$a" ]]; }; then
      resolve_conflict "$a" "目录" "$others"
    fi
    mkdir -p "$a"
    LAYOUT_ARGS+=(--bind "$a" "$p")
  done < <(printf '%s\n' "${ancestors[@]}" | LC_ALL=C sort -u)
  LAYOUT_ARGS+=("${binds[@]}")
}

# 网络命名空间与防火墙规则配置
setup_network_isolation() {
  local slot="$1" ip_host="$2" ip_guest="$3" veth_host="$4" veth_in="$5" netns="$6" chain="$7" plan_json="$8"
  echo 1 > /proc/sys/net/ipv4/ip_forward

  local default_dev
  default_dev="$(ip route show default 2>/dev/null | awk '{print $5}' | head -n 1 || true)"
  [[ -z "$default_dev" ]] && default_dev="eth0"

  iptables -t nat -C POSTROUTING -s 10.200.0.0/16 -o "$default_dev" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s 10.200.0.0/16 -o "$default_dev" -j MASQUERADE
  iptables -P FORWARD DROP
  iptables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
    iptables -I FORWARD 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # 清理旧残留
  iptables -D FORWARD -s "$ip_guest" -j "$chain" 2>/dev/null || true
  iptables -F "$chain" 2>/dev/null || true
  iptables -X "$chain" 2>/dev/null || true
  ip link del "$veth_host" 2>/dev/null || true
  ip netns del "$netns" 2>/dev/null || true

  # 建立 veth 与 netns
  ip netns add "$netns"
  ip link add "$veth_host" type veth peer name "$veth_in"
  ip link set "$veth_in" netns "$netns"

  ip addr add "${ip_host}/30" dev "$veth_host"
  ip link set "$veth_host" up
  ip -n "$netns" addr add "${ip_guest}/30" dev "$veth_in"
  ip -n "$netns" link set "$veth_in" up
  ip -n "$netns" link set lo up
  ip -n "$netns" route add default via "$ip_host"

  # 配置链放行规则
  iptables -N "$chain"
  iptables -A FORWARD -s "$ip_guest" -j "$chain"

  # DNS 放行
  while IFS= read -r dns; do
    if [[ "$dns" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      iptables -A "$chain" -d "$dns" -p udp --dport 53 -j ACCEPT
      iptables -A "$chain" -d "$dns" -p tcp --dport 53 -j ACCEPT
    fi
  done < <(grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')

  # 宿主服务放行
  local host_ip
  host_ip="$(grep 'host.microsandbox.internal' /etc/hosts 2>/dev/null | awk '{print $1}' | grep '^[0-9]' | head -n 1 || true)"
  [[ -z "$host_ip" ]] && host_ip="$(ip route show default 2>/dev/null | awk '{print $3}' | head -n 1 || true)"

  for item in $(jq -r '.default_allow[]? // empty' <<< "$plan_json"); do
    if [[ "$item" =~ ^host:tcp:([0-9]+)$ ]]; then
      local port="${BASH_REMATCH[1]}"
      [[ -n "$host_ip" ]] && iptables -A "$chain" -d "$host_ip" -p tcp --dport "$port" -j ACCEPT
    fi
  done

  # 项目获准私网放行
  for target in $(jq -r '.network[]? // empty' <<< "$plan_json"); do
    if [[ "$target" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)$ ]]; then
      iptables -A "$chain" -d "${BASH_REMATCH[1]}" -p tcp --dport "${BASH_REMATCH[2]}" -j ACCEPT
    elif [[ -n "$target" ]]; then
      iptables -A "$chain" -d "$target" -j ACCEPT
    fi
  done

  # 私网网段全拦截 (家庭网段 192.168.0.0/16 默认在此拦截)
  iptables -A "$chain" -d 10.0.0.0/8 -j REJECT
  iptables -A "$chain" -d 172.16.0.0/12 -j REJECT
  iptables -A "$chain" -d 192.168.0.0/16 -j REJECT
  iptables -A "$chain" -d 100.64.0.0/10 -j REJECT
  iptables -A "$chain" -d 169.254.0.0/16 -j REJECT

  # 放行其余所有公网目标
  iptables -A "$chain" -j ACCEPT
}

# 检查活跃上下文数 (--check-busy)
if [[ "${1:-}" == "--check-busy" ]]; then
  acquire_slot_lock
  sweep_dead_contexts
  count=0
  if [[ -d "$CONTEXTS_DIR" ]]; then
    for ctx_dir in "$CONTEXTS_DIR"/*; do
      [[ -d "$ctx_dir" ]] || continue
      if [[ -f "$ctx_dir/meta.json" ]] || is_starting "$ctx_dir"; then
        count=$((count + 1))
      fi
    done
  fi
  echo "$count"
  release_slot_lock
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

# 1. 槽位锁分配与元数据发布
acquire_slot_lock
sweep_dead_contexts

declare -A USED_SLOTS=()
for ctx_dir in "$CONTEXTS_DIR"/*; do
  [[ -d "$ctx_dir" ]] || continue
  if [[ -f "$ctx_dir/meta.json" ]]; then
    s="$(jq -r '.slot // empty' "$ctx_dir/meta.json" 2>/dev/null || true)"
    [[ -n "$s" && "$s" =~ ^[0-9]+$ ]] && USED_SLOTS["$s"]=1
  fi
done

ALLOCATED_SLOT=-1
for ((i = 0; i < MAX_SLOTS; i++)); do
  if [[ -z "${USED_SLOTS[$i]:-}" ]]; then
    ALLOCATED_SLOT="$i"
    break
  fi
done

if [[ "$ALLOCATED_SLOT" -lt 0 ]]; then
  echo "[-] 错误: 执行上下文地址池已耗尽 (当前上限: $MAX_SLOTS 个并发上下文)" >&2
  release_slot_lock
  exit 1
fi

SLOT="$ALLOCATED_SLOT"
IP_HOST="10.200.$((SLOT / 64)).$(( (SLOT % 64) * 4 + 1 ))"
IP_GUEST="10.200.$((SLOT / 64)).$(( (SLOT % 64) * 4 + 2 ))"
VETH_HOST="vth${SLOT}"
VETH_IN="vth${SLOT}_in"
NETNS="sb_ctx_${SLOT}"
CHAIN="SB_CTX_${SLOT}"

PROJECT_ROOT="$(jq -r '.project_root' <<< "$PLAN_JSON")"
GIT_COMMON_DIR="$(jq -r '.git_common_dir // empty' <<< "$PLAN_JSON")"

CURRENT_CTX_DIR="$CONTEXTS_DIR/$CTX_ID"
mkdir -p "$CURRENT_CTX_DIR"
IMPORTS_DIR="$CURRENT_CTX_DIR/imports"

META_TMP="$CURRENT_CTX_DIR/meta.json.tmp"
jq -n \
  --argjson slot "$SLOT" \
  --argjson pid "$$" \
  --arg ip "$IP_GUEST" \
  --arg veth_host "$VETH_HOST" \
  --arg netns "$NETNS" \
  --arg chain "$CHAIN" \
  '{slot: $slot, pid: $pid, ip: $ip, veth_host: $veth_host, netns: $netns, chain: $chain}' > "$META_TMP"
mv "$META_TMP" "$CURRENT_CTX_DIR/meta.json"
rm -f "$CURRENT_CTX_DIR/starting"

OTHER_CONTEXTS=0
for ctx_dir in "$CONTEXTS_DIR"/*; do
  [[ -d "$ctx_dir" && "$ctx_dir" != "$CURRENT_CTX_DIR" ]] || continue
  if [[ -f "$ctx_dir/meta.json" ]] || is_starting "$ctx_dir"; then
    OTHER_CONTEXTS=$((OTHER_CONTEXTS + 1))
  fi
done

trap 'rm -rf "$CURRENT_CTX_DIR"' EXIT
prepare_declared_layout "$OTHER_CONTEXTS"
release_slot_lock

# 2. 退出清理钩子
cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM HUP
  iptables -D FORWARD -s "$IP_GUEST" -j "$CHAIN" 2>/dev/null || true
  iptables -F "$CHAIN" 2>/dev/null || true
  iptables -X "$CHAIN" 2>/dev/null || true
  ip link del "$VETH_HOST" 2>/dev/null || true
  ip netns del "$NETNS" 2>/dev/null || true
  rm -rf "$CURRENT_CTX_DIR"
  exit "$exit_code"
}
trap cleanup EXIT INT TERM HUP

# 3. 配置网络隔离
setup_network_isolation "$SLOT" "$IP_HOST" "$IP_GUEST" "$VETH_HOST" "$VETH_IN" "$NETNS" "$CHAIN" "$PLAN_JSON"

# 4. 构建 bubblewrap 参数
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

[[ -d /opt/sandbox-mise ]] && BWRAP_ARGS+=(--ro-bind /opt/sandbox-mise /opt/sandbox-mise)
[[ -d /run/sandbox-config ]] && BWRAP_ARGS+=(--ro-bind /run/sandbox-config /run/sandbox-config)

BWRAP_ARGS+=("${LAYOUT_ARGS[@]}")

# 导入文件绑定
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

# 5. 加载工具环境并启动
export GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
export GIT_CONFIG_GLOBAL="${SB_GIT_CONFIG:-}"
if [[ -f /run/sandbox-config/current/guest-env.sh ]]; then
  # shellcheck source=/dev/null
  source /run/sandbox-config/current/guest-env.sh
fi
export MISE_OFFLINE=1

exec ip netns exec "$NETNS" bwrap "${BWRAP_ARGS[@]}" -- "$@"
