#!/usr/bin/env bash
set -euo pipefail

export PATH="/data/xdg/data/mise/shims:@guest_bin_path@"
export HOME="${HOME:-/root}"

CONTEXTS_DIR="/run/sandbox/contexts"
MAX_SLOTS=64
# 宿主复制 imports 的时间窗保护：未超宽限的「启动中」目录视为存活（B）
STARTUP_GRACE_SECS=120
# 上下文目录归属锁：清扫、选槽、meta 发布必须在这把锁内完成（A）
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

# 目录处于宿主复制 imports 阶段：存在 starting 标记且未超宽限
is_starting() {
  local dir="$1"
  [[ -f "$dir/starting" ]] || return 1
  local started
  started="$(stat -c %Y "$dir/starting" 2>/dev/null || echo 0)"
  [[ $(( $(date +%s) - started )) -lt $STARTUP_GRACE_SECS ]]
}

# 1. 残留清扫逻辑：检查所有已登记上下文，清理死进程残留；清理无归属的孤儿网络资源
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
    # 无 meta 的目录可能正被宿主复制 imports：宽限内视为存活（B）
    if [[ "$is_alive" -eq 0 && ! -f "$meta" ]] && is_starting "$ctx_dir"; then
      is_alive=1
    fi

    if [[ "$is_alive" -eq 0 ]]; then
      # 进程已死亡，清除对应的 iptables 规则、veth、netns 与登记目录
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

  # 扫描并清理孤儿 netns (以 sb_ctx_ 开头但无登记上下文)
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

if [[ "${1:-}" == "--check-busy" ]]; then
  acquire_slot_lock
  sweep_dead_contexts
  count=0
  if [[ -d "$CONTEXTS_DIR" ]]; then
    for ctx_dir in "$CONTEXTS_DIR"/*; do
      [[ -d "$ctx_dir" ]] || continue
      # 启动中的目录在宽限内同样占用 VM，计入忙碌（B）
      if [[ -f "$ctx_dir/meta.json" ]] || is_starting "$ctx_dir"; then
        count=$((count + 1))
      fi
    done
  fi
  echo "$count"
  release_slot_lock
  exit 0
fi

# 子命令 2: 列出活跃上下文元数据
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
# netns/veth/iptables（A）
acquire_slot_lock
sweep_dead_contexts

mkdir -p "$CONTEXTS_DIR"

# 2. 地址池与槽位分配 (找到最小未占用的 slot)
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

# 3. 登记当前上下文元数据：jq 生成（转义路径中的引号/换行，合法路径不产生
# 损坏的 JSON），写临时文件后 mv 原子发布（D），并移除宿主侧「启动中」标记；
# 此后目录所有权归属本 launcher（B）
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
release_slot_lock

# 4. 退出清理钩子 (异常与正常退出均触发)
cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM HUP

  # 归属校验：只删除本次启动确实创建的资源（A）。槽位冲突时 meta 归属另一
  # launcher，删除同名 netns/veth/chain 会拆掉另一个运行中的上下文
  local owned=0
  if [[ -f "$CURRENT_CTX_DIR/meta.json" ]] && [[ "$(jq -r '.pid // 0' "$CURRENT_CTX_DIR/meta.json" 2>/dev/null || echo 0)" == "$$" ]]; then
    owned=1
  fi
  if [[ "$owned" -eq 1 ]]; then
    # 删除 iptables 规则与专用链
    iptables -D FORWARD -s "$IP_GUEST" -j "$CHAIN" 2>/dev/null || true
    iptables -F "$CHAIN" 2>/dev/null || true
    iptables -X "$CHAIN" 2>/dev/null || true

    # 删除 veth 与 netns
    ip link del "$VETH_HOST" 2>/dev/null || true
    ip netns del "$NETNS" 2>/dev/null || true
  fi

  # 删除导入文件与登记目录
  rm -rf "$CURRENT_CTX_DIR"

  exit "$exit_code"
}
trap cleanup EXIT INT TERM HUP

# 5. 网络环境搭建 (netns + veth + NAT + FORWARD)
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

# 6. 配置上下文专有 iptables 链 (规则只按源地址匹配)
iptables -N "$CHAIN"
iptables -A FORWARD -s "$IP_GUEST" -j "$CHAIN"

# a. 默认放行 DNS (来自 /etc/resolv.conf 的 nameserver)
while IFS= read -r dns; do
  if [[ "$dns" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    iptables -A "$CHAIN" -d "$dns" -p udp --dport 53 -j ACCEPT
    iptables -A "$CHAIN" -d "$dns" -p tcp --dport 53 -j ACCEPT
  fi
done < <(grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')

# b. 默认放行宿主端口 (如 host:tcp:3425, host:tcp:8080)
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

# c. 放行项目在 .sandbox.yaml 中显式声明的私网目标
for target in $(jq -r '.network[]? // empty' <<< "$PLAN_JSON"); do
  if [[ "$target" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)$ ]]; then
    ip="${BASH_REMATCH[1]}"
    port="${BASH_REMATCH[2]}"
    iptables -A "$CHAIN" -d "$ip" -p tcp --dport "$port" -j ACCEPT
  elif [[ -n "$target" ]]; then
    iptables -A "$CHAIN" -d "$target" -j ACCEPT
  fi
done

# d. 拦截未声明的所有私网与保留网段 (家庭网段 192.168.0.0/16 默认落在此处拦截)
iptables -A "$CHAIN" -d 10.0.0.0/8 -j REJECT
iptables -A "$CHAIN" -d 172.16.0.0/12 -j REJECT
iptables -A "$CHAIN" -d 192.168.0.0/16 -j REJECT
iptables -A "$CHAIN" -d 100.64.0.0/10 -j REJECT
iptables -A "$CHAIN" -d 169.254.0.0/16 -j REJECT

# e. 放行其余所有公网目标 (包括假 IP 代理 198.18.0.0/15 与外部公网)
iptables -A "$CHAIN" -j ACCEPT

# 7. 组装 bubblewrap 隔离参数
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

# 共享可写状态卷 /data
if [[ -d /data ]]; then
  BWRAP_ARGS+=(--bind /data /data)
  # OMP 只在 $XDG_*_HOME/omp 已存在时使用 XDG 路径，否则回落到只读的 ~/.omp/agent 而无法建库
  mkdir -p /data/xdg/data/omp /data/xdg/state/omp /data/xdg/cache/omp /data/xdg/config /data/mise /data/omp/plugins /data/xdg/data/mise/shims
  # 同理插件目录：XDG 生效后 OMP 读 $XDG_DATA_HOME/omp/plugins，安装位置 /data/omp/plugins 需链到这里
  ln -sfn /data/omp/plugins /data/xdg/data/omp/plugins
fi

# 宿主共用 mise 目录：执行上下文内只读，安装仅经 sb sync
if [[ -d /opt/sandbox-mise ]]; then
  BWRAP_ARGS+=(--ro-bind /opt/sandbox-mise /opt/sandbox-mise)
fi

# 沙箱配置目录 (如果存在)
if [[ -d /run/sandbox-config ]]; then
  BWRAP_ARGS+=(--ro-bind /run/sandbox-config /run/sandbox-config)
  if [[ -e /run/sandbox-config/current/.omp ]]; then
    BWRAP_ARGS+=(
      --dir /root/.omp
      --symlink /run/sandbox-config/current/.omp/agent /root/.omp/agent
      --symlink /data/omp/plugins /root/.omp/plugins
    )
  fi
  if [[ -e /run/sandbox-config/current/.agents ]]; then
    BWRAP_ARGS+=(--symlink /run/sandbox-config/current/.agents /root/.agents)
  fi
  if [[ -e /run/sandbox-config/current/.pi ]]; then
    BWRAP_ARGS+=(--symlink /run/sandbox-config/current/.pi /root/.pi)
  fi
fi

# 导入文件：每个目标目录绑定一份暂存目录（目录形式支持原子改名；退出自动删除）。
# 目标目录会被整体遮住，所以不能落在系统目录或 launcher 自己铺设的配置链接上
while IFS=$'\t' read -r stage dir; do
  [[ -n "$stage" ]] || continue
  dir="${dir/#\~/$HOME}"
  case "$dir" in
    "$HOME" | / | /usr | /usr/* | /bin | /bin/* | /lib | /lib/* | /lib64 | /lib64/* | /etc | /etc/* | \
      /proc | /proc/* | /dev | /dev/* | /run | /run/* | /nix | /nix/* | /opt | /opt/* | /data | /data/* | \
      /.msb | /.msb/* | "$HOME/.omp" | "$HOME/.omp/"* | "$HOME/.agents" | "$HOME/.agents/"* | "$HOME/.pi" | "$HOME/.pi/"*)
      echo "[-] 错误: imports 的目标目录 $dir 是沙箱保留位置" >&2
      exit 1
      ;;
  esac
  BWRAP_ARGS+=(--bind "$IMPORTS_DIR/$stage" "$dir")
done < <(jq -r '[.imports[]? | [.stage, .dir]] | unique[] | @tsv' <<< "$PLAN_JSON")

# 绑定当前项目根目录 (相邻未绑定项目在视图中不可见)
BWRAP_ARGS+=(--bind "$PROJECT_ROOT" "$PROJECT_ROOT")

# 若存在项目根外的 git common dir，自动加绑
if [[ -n "$GIT_COMMON_DIR" && "$GIT_COMMON_DIR" != "$PROJECT_ROOT" && "$GIT_COMMON_DIR" != "$PROJECT_ROOT"/* ]]; then
  if [[ -e "$GIT_COMMON_DIR" ]]; then
    BWRAP_ARGS+=(--bind "$GIT_COMMON_DIR" "$GIT_COMMON_DIR")
  fi
fi

# 绑定声明的额外路径 paths
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

# 设置工作目录
if [[ -d "$CWD" ]]; then
  BWRAP_ARGS+=(--chdir "$CWD")
else
  BWRAP_ARGS+=(--chdir "$PROJECT_ROOT")
fi

# 8. 环境变量与命令执行
# 唯一来源：/run/sandbox-config/current/guest-env.sh（generator 单一生成）。
# 这里不再维护第二份回退：缺少该文件说明 VM 未挂载生成配置，
# 此时 PATH 只有基础工具（未声明任何共享工具），行为与单元 2 一次性 VM 一致。
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
# 依据参数形式分流：单字符串含复杂语法走 bash -c，多参数直接 exec
if [[ $# -eq 0 ]]; then
  set -- bash
fi

if [[ $# -eq 1 && ("$1" =~ [[:space:]\|\&\;\<\>] || ! -x "$(command -v "$1" 2>/dev/null || true)") ]]; then
  ip netns exec "$NETNS" bwrap "${BWRAP_ARGS[@]}" -- bash -c "$1"
else
  ip netns exec "$NETNS" bwrap "${BWRAP_ARGS[@]}" -- "$@"
fi