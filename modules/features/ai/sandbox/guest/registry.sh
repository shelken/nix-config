#!/usr/bin/env bash
# guest/registry.sh: 上下文注册表与槽位生命周期管理
# 职责：
# 1. 槽位锁管理 (acquire_slot_lock, release_slot_lock)
# 2. 扫除僵死上下文 (sweep_dead_contexts)
# 3. 槽位原子分配与元数据发布 (allocate_slot)
# 4. 退出资源回收与槽位归还 (release_slot)
set -euo pipefail

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
  local keep="${1:-}"
  [[ -d "$CONTEXTS_DIR" ]] || return 0
  for ctx_dir in "$CONTEXTS_DIR"/*; do
    [[ -d "$ctx_dir" ]] || continue
    local name="${ctx_dir##*/}"
    [[ -n "$keep" && "$name" == "$keep" ]] && continue

    local meta="$ctx_dir/meta.json"
    if [[ ! -f "$meta" ]]; then
      if is_starting "$ctx_dir"; then
        continue
      fi
      rm -rf "$ctx_dir"
      continue
    fi
    local pid slot
    pid="$(jq -r '.pid // empty' "$meta" 2>/dev/null || true)"
    slot="$(jq -r '.slot // empty' "$meta" 2>/dev/null || true)"
    if [[ -z "$pid" || ! -d "/proc/$pid" ]]; then
      [[ -n "$slot" ]] && net_down "$slot"
      rm -rf "$ctx_dir"
    fi
  done
}

count_active_contexts() {
  acquire_slot_lock
  sweep_dead_contexts
  local count=0
  if [[ -d "$CONTEXTS_DIR" ]]; then
    for ctx_dir in "$CONTEXTS_DIR"/*; do
      [[ -d "$ctx_dir" ]] || continue
      if [[ -f "$ctx_dir/meta.json" ]] || is_starting "$ctx_dir"; then
        count=$((count + 1))
      fi
    done
  fi
  release_slot_lock
  echo "$count"
}

allocate_slot() {
  local ctx_id="$1" plan_json="$2"
  acquire_slot_lock
  sweep_dead_contexts "$ctx_id"

  declare -A used_slots=()
  for ctx_dir in "$CONTEXTS_DIR"/*; do
    [[ -d "$ctx_dir" ]] || continue
    if [[ -f "$ctx_dir/meta.json" ]]; then
      local s
      s="$(jq -r '.slot // empty' "$ctx_dir/meta.json" 2>/dev/null || true)"
      [[ -n "$s" && "$s" =~ ^[0-9]+$ ]] && used_slots["$s"]=1
    fi
  done

  local allocated_slot=-1
  for ((i = 0; i < MAX_SLOTS; i++)); do
    if [[ -z "${used_slots[$i]:-}" ]]; then
      allocated_slot="$i"
      break
    fi
  done

  if [[ "$allocated_slot" -lt 0 ]]; then
    echo "[-] 错误: 执行上下文地址池已耗尽 (当前上限: $MAX_SLOTS 个并发上下文)" >&2
    release_slot_lock
    exit 1
  fi

  CURRENT_SLOT="$allocated_slot"
  calc_slot_network "$CURRENT_SLOT"

  CURRENT_CTX_DIR="$CONTEXTS_DIR/$ctx_id"
  mkdir -p "$CURRENT_CTX_DIR"

  local meta_tmp="$CURRENT_CTX_DIR/meta.json.tmp"
  jq -n \
    --argjson slot "$CURRENT_SLOT" \
    --argjson pid "$$" \
    --arg ip "$SLOT_IP_GUEST" \
    --arg veth_host "$SLOT_VETH_HOST" \
    --arg netns "$SLOT_NETNS" \
    --arg chain "$SLOT_CHAIN" \
    '{slot: $slot, pid: $pid, ip: $ip, veth_host: $veth_host, netns: $netns, chain: $chain}' > "$meta_tmp"
  mv "$meta_tmp" "$CURRENT_CTX_DIR/meta.json"
  rm -f "$CURRENT_CTX_DIR/starting"

  OTHER_CONTEXTS_COUNT=0
  for ctx_dir in "$CONTEXTS_DIR"/*; do
    [[ -d "$ctx_dir" && "$ctx_dir" != "$CURRENT_CTX_DIR" ]] || continue
    if [[ -f "$ctx_dir/meta.json" ]] || is_starting "$ctx_dir"; then
      OTHER_CONTEXTS_COUNT=$((OTHER_CONTEXTS_COUNT + 1))
    fi
  done

  # 准备并启动网络隔离
  net_up "$CURRENT_SLOT" "$plan_json"
}

release_slot() {
  local ctx_id="$1" slot="${2:-}"
  if [[ -z "$slot" && -f "$CONTEXTS_DIR/$ctx_id/meta.json" ]]; then
    slot="$(jq -r '.slot // empty' "$CONTEXTS_DIR/$ctx_id/meta.json" 2>/dev/null || true)"
  fi
  [[ -n "$slot" ]] && net_down "$slot"
  rm -rf "${CONTEXTS_DIR:?}/${ctx_id:?}"
}
