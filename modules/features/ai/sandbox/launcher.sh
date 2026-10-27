#!/usr/bin/env bash
set -euo pipefail

export PATH="/data/xdg/data/mise/shims:@guest_bin_path@"
export HOME="${HOME:-/root}"

CONTEXTS_DIR="/run/sandbox/contexts"
MAX_SLOTS=64
# 宿主复制 imports 的时间窗保护：未超宽限的「启动中」目录视为存活
STARTUP_GRACE_SECS=120
SLOT_LOCK="$CONTEXTS_DIR/.slot.lock"

acquire_slot_lock() {
  mkdir -p "$CONTEXTS_DIR"
  exec 9>>"$SLOT_LOCK"
  flock -w 30 9
}

release_slot_lock() {
  flock -u 9 2>/dev/null || true
  exec 9>&-
}

is_starting() {
  local dir="$1"
  [[ -f "$dir/starting" ]] || return 1
  local started
  started="$(stat -c %Y "$dir/starting" 2>/dev/null || echo 0)"
  [[ $(( $(date +%s) - started )) -lt $STARTUP_GRACE_SECS ]]
}

sweep_dead_contexts() {
  if [[ ! -d "$CONTEXTS_DIR" ]]; then
    return 0
  fi

  for ctx_dir in "$CONTEXTS_DIR"/*; do
    [[ -d "$ctx_dir" ]] || continue
    if [[ -n "${CURRENT_CTX_ID:-}" && "$ctx_dir" == "$CONTEXTS_DIR/$CURRENT_CTX_ID" ]]; then
      continue
    fi
    local meta="$ctx_dir/meta.json"
    local pid="" ip="" veth_host="" netns="" chain=""
    if [[ -f "$meta" ]]; then
      pid="$(jq -r '.pid // empty' "$meta" 2>/dev/null || true)"
      ip="$(jq -r '.ip // empty' "$meta" 2>/dev/null || true)"
      veth_host="$(jq -r '.veth_host // empty' "$meta" 2>/dev/null || true)"
      netns="$(jq -r '.netns // empty' "$meta" 2>/dev/null || true)"
      chain="$(jq -r '.chain // empty' "$meta" 2>/dev/null || true)"
    fi

    local is_alive=0
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      is_alive=1
    fi
    # 无 meta 的目录可能正被宿主复制 imports：宽限内视为存活
    if [[ "$is_alive" -eq 0 && ! -f "$meta" ]] && is_starting "$ctx_dir"; then
      is_alive=1
    fi

    if [[ "$is_alive" -eq 0 ]]; then
      if [[ -n "$ip" && -n "$chain" ]]; then
        iptables -D FORWARD -s "$ip" -j "$chain" 2>/dev/null || true
      fi
      if [[ -n "$chain" ]]; then
        iptables -F "$chain" 2>/dev/null || true
        iptables -X "$chain" 2>/dev/null || true
      fi
      if [[ -n "$veth_host" ]]; then
        ip link del "$veth_host" 2>/dev/null || true
      fi
      if [[ -n "$netns" ]]; then
        ip netns del "$netns" 2>/dev/null || true
      fi
      rm -rf "$ctx_dir"
    fi
  done

  for ns in $(ip netns list 2>/dev/null | awk '{print $1}' | grep '^sb_ctx_' || true); do
    local found=0
    for ctx_dir in "$CONTEXTS_DIR"/*; do
      [[ -d "$ctx_dir" ]] || continue
      if [[ -f "$ctx_dir/meta.json" ]]; then
        local reg_ns
        reg_ns="$(jq -r '.netns // empty' "$ctx_dir/meta.json" 2>/dev/null || true)"
        if [[ "$reg_ns" == "$ns" ]]; then
          found=1
          break
        fi
      fi
    done
    if [[ "$found" -eq 0 ]]; then
      ip netns del "$ns" 2>/dev/null || true
    fi
  done

  # 扫描并清理孤儿 veth 接口 (以 vth 开头但无对应登记)；veth 在 ip -o link 中带 @peer 后缀，先截断再匹配
  for veth in $(ip -o link show 2>/dev/null | awk -F': ' '{sub(/@.*/, "", $2); print $2}' | grep -E '^vth[0-9]+$' || true); do
    local found=0
    for ctx_dir in "$CONTEXTS_DIR"/*; do
      [[ -d "$ctx_dir" ]] || continue
      if [[ -f "$ctx_dir/meta.json" ]]; then
        local reg_veth
        reg_veth="$(jq -r '.veth_host // empty' "$ctx_dir/meta.json" 2>/dev/null || true)"
        if [[ "$reg_veth" == "$veth" ]]; then
          found=1
          break
        fi
      fi
    done
    if [[ "$found" -eq 0 ]]; then
      ip link del "$veth" 2>/dev/null || true
    fi
  done
}

# 可写根：agent 配置目录整体落在数据盘、所有上下文共用；其中 Nix 声明的路径再逐项只读挂载。
# 根的清单来自发布目录的 writable-roots（登记表 shelken.dev.sandbox.writableRoots），
# launcher 自己不带任何路径，只按固定规则映射到数据盘：$HOME/<相对根> -> /data/home/<相对根>
declare -A AGENT_ROOTS=()

# 上下文路径 -> 数据盘上的同一位置（挂载点占位所在）。.config/<X> 映射到 $XDG_CONFIG_HOME/<X>
declared_dst() {
  case "$1" in
    .config/*) echo "/data/xdg/config/${1#.config/}" ;;
    *) echo "$HOME/$1" ;;
  esac
}

backing_of() {
  local p="$1" root
  for root in "${!AGENT_ROOTS[@]}"; do
    if [[ "$p" == "$root" || "$p" == "$root/"* ]]; then
      echo "${AGENT_ROOTS[$root]}${p#"$root"}"
      return
    fi
  done
  echo "$p"
}

mount_root_of() {
  local p="$1" root
  for root in "${!AGENT_ROOTS[@]}"; do
    if [[ "$p" == "$root/"* ]]; then
      echo "$root"
      return
    fi
  done
  [[ "$p" == /data/* ]] || return 1
  echo /data
}

is_empty_placeholder() {
  [[ ! -L "$1" ]] || return 1
  if [[ -d "$1" ]]; then
    [[ -z "$(ls -A "$1")" ]]
  else
    [[ -f "$1" && ! -s "$1" ]]
  fi
}

resolve_conflict() {
  local path="$1" want="$2" others="$3"
  if is_empty_placeholder "$path" && [[ "$others" -eq 0 ]]; then
    rm -rf "$path"
    return
  fi
  if is_empty_placeholder "$path"; then
    echo "[-] 错误: 声明配置的落点 $path 残留了类型不符的空占位（需要$want），但还有 $others 个上下文在运行，可能正把它当挂载点用；全部退出后重试" >&2
  else
    echo "[-] 错误: 声明配置的落点 $path 已有类型不符的内容（需要$want），不会自动删除；确认无用后手动移走" >&2
  fi
  exit 1
}

# 布局结果：bwrap 参数，以及需要变成挂载点的目录（导入目标不得落在其下）
LAYOUT_ARGS=()
MOUNT_POINTS=()

is_agent_layout_path() {
  local d="$1" p
  for p in "${MOUNT_POINTS[@]}" "${!AGENT_ROOTS[@]}"; do
    if [[ "$d" == "$p" || "$d" == "$p/"* ]]; then
      return 0
    fi
  done
  return 1
}

# 发布目录在而清单缺失时不能静默放行：上下文会没有任何声明配置和只读保护
require_published() {
  if [[ ! -f "$1" ]]; then
    echo "[-] 错误: 发布目录缺少清单：$1（发布目录来自旧版本，重新发布配置后重试：just hm）" >&2
    exit 1
  fi
}

# agent 配置布局（启动锁内调用）：读发布清单，整理数据盘上的落点，生成 LAYOUT_ARGS：
# tmpfs $HOME -> 根的上层目录（tmpfs）-> 可写根（数据盘）-> 声明配置的祖先目录 -> 声明配置逐项只读。
# 上层目录与祖先目录都要变成挂载点：内核只拒绝改名挂载点本身，
# 改名普通祖先会把下面的挂载一起移走，原位置就能建出可写的同名替身
prepare_declared_layout() {
  local others="$1" cfg list roots_file rel t dst src want root p a
  local -a ancestors=() binds=() uppers=()
  [[ -e /run/sandbox-config/current ]] || return 0
  # 只解析一次 current：清单与挂载源来自同一版本，宿主中途重新发布也不会错位
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
  # 父目录排在子目录前面：C 排序下前缀先于其延伸
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
      echo "[-] 错误: 声明配置 $t 不在任何可写根或 .config/ 下（发布清单不一致，重新发布配置后重试：just hm）" >&2
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

if [[ "${1:-}" == "--check-busy" ]]; then
  acquire_slot_lock
  sweep_dead_contexts
  count=0
  if [[ -d "$CONTEXTS_DIR" ]]; then
    for ctx_dir in "$CONTEXTS_DIR"/*; do
      [[ -d "$ctx_dir" ]] || continue
      # 启动中的目录在宽限内同样占用 VM，计入忙碌
      if [[ -f "$ctx_dir/meta.json" ]] || is_starting "$ctx_dir"; then
        count=$((count + 1))
      fi
    done
  fi
  echo "$count"
  release_slot_lock
  exit 0
fi

if [[ "${1:-}" == "--list-contexts" ]]; then
  acquire_slot_lock
  sweep_dead_contexts
  res="[]"
  items=()
  if [[ -d "$CONTEXTS_DIR" ]]; then
    items=()
    for ctx_dir in "$CONTEXTS_DIR"/*; do
      [[ -d "$ctx_dir" ]] || continue
      if [[ -f "$ctx_dir/meta.json" ]]; then
        items+=("$(cat "$ctx_dir/meta.json")")
      fi
    done
    if [[ ${#items[@]} -gt 0 ]]; then
      res="$(printf '%s\n' "${items[@]}" | jq -s .)"
    fi
  fi
  echo "$res"
  release_slot_lock
  exit 0
fi

if [[ $# -lt 3 ]]; then
  echo "[-] 错误: sb-launcher 参数不足。用法: sb-launcher <ctx_id> <plan_json> <cwd> [cmd...]" >&2
  exit 1
fi

CTX_ID="$1"
CURRENT_CTX_ID="$1"
PLAN_JSON="$2"
CWD="$3"
shift 3

# 启动临界区：死上下文清扫、选槽、meta.json 原子发布在同一把短期锁内串行，
# 否则并发 launcher 会选中同一槽位，失败方的清理会误删另一上下文的
# netns/veth/iptables
acquire_slot_lock
sweep_dead_contexts

mkdir -p "$CONTEXTS_DIR"

declare -A USED_SLOTS=()
for ctx_dir in "$CONTEXTS_DIR"/*; do
  [[ -d "$ctx_dir" ]] || continue
  if [[ -f "$ctx_dir/meta.json" ]]; then
    s="$(jq -r '.slot // empty' "$ctx_dir/meta.json" 2>/dev/null || true)"
    if [[ -n "$s" && "$s" =~ ^[0-9]+$ ]]; then
      USED_SLOTS["$s"]=1
    fi
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
# 宿主在复制 imports 时已建好该目录；没有 imports 时它不存在
IMPORTS_DIR="$CURRENT_CTX_DIR/imports"

# 登记元数据：路径可含引号或换行，所以用 jq 生成合法 JSON；写临时文件后 mv 原子发布，
# 并移除宿主侧「启动中」标记，此后目录所有权归属本 launcher
META_TMP="$CURRENT_CTX_DIR/meta.json.tmp"
jq -n \
  --arg id "$CTX_ID" \
  --argjson slot "$SLOT" \
  --argjson pid "$$" \
  --arg project_root "$PROJECT_ROOT" \
  --arg created_at "$(date -Iseconds)" \
  --arg ip "$IP_GUEST" \
  --arg veth_host "$VETH_HOST" \
  --arg veth_in "$VETH_IN" \
  --arg netns "$NETNS" \
  --arg chain "$CHAIN" \
  '{id: $id, slot: $slot, pid: $pid, project_root: $project_root, created_at: $created_at,
    ip: $ip, veth_host: $veth_host, veth_in: $veth_in, netns: $netns, chain: $chain}' > "$META_TMP"
mv "$META_TMP" "$CURRENT_CTX_DIR/meta.json"
rm -f "$CURRENT_CTX_DIR/starting"

# 声明配置布局要在锁内整理：删除残留占位前必须确认没有别的上下文正把它当挂载点用
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

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM HUP

  # 归属校验：只删除本次启动确实创建的资源。槽位冲突时 meta 归属另一
  # launcher，删除同名 netns/veth/chain 会拆掉另一个运行中的上下文
  local owned=0
  if [[ -f "$CURRENT_CTX_DIR/meta.json" ]] && [[ "$(jq -r '.pid // 0' "$CURRENT_CTX_DIR/meta.json" 2>/dev/null || echo 0)" == "$$" ]]; then
    owned=1
  fi
  if [[ "$owned" -eq 1 ]]; then
    iptables -D FORWARD -s "$IP_GUEST" -j "$CHAIN" 2>/dev/null || true
    iptables -F "$CHAIN" 2>/dev/null || true
    iptables -X "$CHAIN" 2>/dev/null || true

    ip link del "$VETH_HOST" 2>/dev/null || true
    ip netns del "$NETNS" 2>/dev/null || true
  fi

  rm -rf "$CURRENT_CTX_DIR"

  exit "$exit_code"
}
trap cleanup EXIT INT TERM HUP

echo 1 > /proc/sys/net/ipv4/ip_forward

DEFAULT_DEV="$(ip route show default 2>/dev/null | awk '{print $5}' | head -n 1 || true)"
if [[ -z "$DEFAULT_DEV" ]]; then DEFAULT_DEV="eth0"; fi

iptables -t nat -C POSTROUTING -s 10.200.0.0/16 -o "$DEFAULT_DEV" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s 10.200.0.0/16 -o "$DEFAULT_DEV" -j MASQUERADE
iptables -P FORWARD DROP
iptables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
  iptables -I FORWARD 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

ip netns add "$NETNS"
ip link add "$VETH_HOST" type veth peer name "$VETH_IN"
ip link set "$VETH_IN" netns "$NETNS"

ip addr add "${IP_HOST}/30" dev "$VETH_HOST"
ip link set "$VETH_HOST" up
ip -n "$NETNS" addr add "${IP_GUEST}/30" dev "$VETH_IN"
ip -n "$NETNS" link set "$VETH_IN" up
ip -n "$NETNS" link set lo up
ip -n "$NETNS" route add default via "$IP_HOST"

iptables -N "$CHAIN"
iptables -A FORWARD -s "$IP_GUEST" -j "$CHAIN"

while IFS= read -r dns; do
  if [[ "$dns" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    iptables -A "$CHAIN" -d "$dns" -p udp --dport 53 -j ACCEPT
    iptables -A "$CHAIN" -d "$dns" -p tcp --dport 53 -j ACCEPT
  fi
done < <(grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')

HOST_IP="$(grep 'host.microsandbox.internal' /etc/hosts 2>/dev/null | awk '{print $1}' | grep '^[0-9]' | head -n 1 || true)"
if [[ -z "$HOST_IP" ]]; then
  HOST_IP="$(ip route show default 2>/dev/null | awk '{print $3}' | head -n 1 || true)"
fi
for item in $(jq -r '.default_allow[]? // empty' <<< "$PLAN_JSON"); do
  if [[ "$item" =~ ^host:tcp:([0-9]+)$ ]]; then
    port="${BASH_REMATCH[1]}"
    if [[ -n "$HOST_IP" ]]; then
      iptables -A "$CHAIN" -d "$HOST_IP" -p tcp --dport "$port" -j ACCEPT
    fi
  fi
done

for target in $(jq -r '.network[]? // empty' <<< "$PLAN_JSON"); do
  if [[ "$target" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)$ ]]; then
    ip="${BASH_REMATCH[1]}"
    port="${BASH_REMATCH[2]}"
    iptables -A "$CHAIN" -d "$ip" -p tcp --dport "$port" -j ACCEPT
  elif [[ -n "$target" ]]; then
    iptables -A "$CHAIN" -d "$target" -j ACCEPT
  fi
done

# 规则按顺序匹配：放行规则已在前面加好，私网 REJECT 必须排在其后（家庭网段 192.168.0.0/16 默认在此拦截）
iptables -A "$CHAIN" -d 10.0.0.0/8 -j REJECT
iptables -A "$CHAIN" -d 172.16.0.0/12 -j REJECT
iptables -A "$CHAIN" -d 192.168.0.0/16 -j REJECT
iptables -A "$CHAIN" -d 100.64.0.0/10 -j REJECT
iptables -A "$CHAIN" -d 169.254.0.0/16 -j REJECT

# 放行其余所有公网目标 (包括假 IP 代理 198.18.0.0/15 与外部公网)
iptables -A "$CHAIN" -j ACCEPT

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
  # msb 设置的 NODE_EXTRA_CA_CERTS 指向这里；路径缺失时 OMP 的模型发现全部失败
  --ro-bind-try /.msb/tls /.msb/tls
)

if [[ -d /data ]]; then
  BWRAP_ARGS+=(--bind /data /data)
  # OMP 只在 $XDG_*_HOME/omp 已存在时使用 XDG 路径；保持 XDG 布局，插件目录才与 sb sync 的安装位置一致
  mkdir -p /data/xdg/data/omp /data/xdg/state/omp /data/xdg/cache/omp /data/xdg/config /data/mise /data/xdg/data/mise/shims
fi

# 宿主共用 mise 目录：执行上下文内只读，安装仅经 sb sync
if [[ -d /opt/sandbox-mise ]]; then
  BWRAP_ARGS+=(--ro-bind /opt/sandbox-mise /opt/sandbox-mise)
fi

if [[ -d /run/sandbox-config ]]; then
  BWRAP_ARGS+=(--ro-bind /run/sandbox-config /run/sandbox-config)
fi

# agent 配置布局（tmpfs 挂载点、可写根、声明配置）全部由 prepare_declared_layout 按发布清单生成。
# 必须排在 imports 之前，否则后铺的 tmpfs 会遮住 imports 落在 ~ 下的目标
BWRAP_ARGS+=("${LAYOUT_ARGS[@]}")

# 导入文件：每个目标目录绑定一份暂存目录（目录形式支持原子改名；退出自动删除）。
# 目标目录会被整体遮住，所以不能落在系统目录或 launcher 自己铺设的 agent 配置目录上
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
  if [[ -e "$GIT_COMMON_DIR" ]]; then
    BWRAP_ARGS+=(--bind "$GIT_COMMON_DIR" "$GIT_COMMON_DIR")
  fi
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

# 唯一来源：/run/sandbox-config/current/guest-env.sh（generator 单一生成）。
# 缺少该文件说明 VM 未挂载生成配置：不加载工具环境，也不维护第二份回退。
export GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
export GIT_CONFIG_GLOBAL="@git_config@"
if [[ -f /run/sandbox-config/current/guest-env.sh ]]; then
  # shellcheck source=/dev/null
  source /run/sandbox-config/current/guest-env.sh
fi
# 上下文不能安装工具，联网解析项目 mise.toml 里的 latest 没有意义，反而每次启动都白等：
# minio/mc 的版本列表约 14 MB，超过 mise 的超时，缓存写不进去，每次重试并刷警告。
# 写在这里而不是 guest-env.sh：sb sync 也 source 它，但 sync 在上下文外，必须联网
export MISE_OFFLINE=1
if [[ $# -eq 0 ]]; then
  set -- bash
fi

if [[ $# -eq 1 && ("$1" =~ [[:space:]\|\&\;\<\>] || ! -x "$(command -v "$1" 2>/dev/null || true)") ]]; then
  ip netns exec "$NETNS" bwrap "${BWRAP_ARGS[@]}" -- bash -c "$1"
else
  ip netns exec "$NETNS" bwrap "${BWRAP_ARGS[@]}" -- "$@"
fi