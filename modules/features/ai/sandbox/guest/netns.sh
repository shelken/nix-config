#!/usr/bin/env bash
# guest/netns.sh: 上下文网络隔离与防火墙规则管理
# 职责：
# 1. 唯一网络参数推导 (calc_slot_network)
# 2. 网络命名空间、veth 虚拟网卡与 iptables 安全放行规则配置 (net_up)，放行目标读 PLAN_DEFAULT_ALLOW、PLAN_NETWORK
# 3. 统一的网络资源拆卸与清理 (net_down)
set -euo pipefail

calc_slot_network() {
  local slot="$1"
  SLOT_IP_HOST="10.200.$((slot / 64)).$(( (slot % 64) * 4 + 1 ))"
  SLOT_IP_GUEST="10.200.$((slot / 64)).$(( (slot % 64) * 4 + 2 ))"
  SLOT_VETH_HOST="vth${slot}"
  SLOT_VETH_IN="vth${slot}_in"
  SLOT_NETNS="sb_ctx_${slot}"
  SLOT_CHAIN="SB_CTX_${slot}"
}

net_down() {
  local slot="$1"
  calc_slot_network "$slot"
  iptables -D FORWARD -s "$SLOT_IP_GUEST" -j "$SLOT_CHAIN" 2>/dev/null || true
  iptables -F "$SLOT_CHAIN" 2>/dev/null || true
  iptables -X "$SLOT_CHAIN" 2>/dev/null || true
  ip link del "$SLOT_VETH_HOST" 2>/dev/null || true
  ip netns del "$SLOT_NETNS" 2>/dev/null || true
}

net_up() {
  local slot="$1"
  calc_slot_network "$slot"

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
  net_down "$slot"

  # 建立 veth 与 netns
  ip netns add "$SLOT_NETNS"
  ip link add "$SLOT_VETH_HOST" type veth peer name "$SLOT_VETH_IN"
  ip link set "$SLOT_VETH_IN" netns "$SLOT_NETNS"

  ip addr add "${SLOT_IP_HOST}/30" dev "$SLOT_VETH_HOST"
  ip link set "$SLOT_VETH_HOST" up
  ip -n "$SLOT_NETNS" addr add "${SLOT_IP_GUEST}/30" dev "$SLOT_VETH_IN"
  ip -n "$SLOT_NETNS" link set "$SLOT_VETH_IN" up
  ip -n "$SLOT_NETNS" link set lo up
  ip -n "$SLOT_NETNS" route add default via "$SLOT_IP_HOST"

  # 配置链放行规则
  iptables -N "$SLOT_CHAIN"
  iptables -A FORWARD -s "$SLOT_IP_GUEST" -j "$SLOT_CHAIN"

  # DNS 放行
  while IFS= read -r dns; do
    if [[ "$dns" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      iptables -A "$SLOT_CHAIN" -d "$dns" -p udp --dport 53 -j ACCEPT
      iptables -A "$SLOT_CHAIN" -d "$dns" -p tcp --dport 53 -j ACCEPT
    fi
  done < <(grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')

  # 宿主服务放行
  local host_ip
  host_ip="$(grep 'host.microsandbox.internal' /etc/hosts 2>/dev/null | awk '{print $1}' | grep '^[0-9]' | head -n 1 || true)"
  [[ -z "$host_ip" ]] && host_ip="$(ip route show default 2>/dev/null | awk '{print $3}' | head -n 1 || true)"

  for item in "${PLAN_DEFAULT_ALLOW[@]}"; do
    if [[ "$item" =~ ^host:tcp:([0-9]+)$ ]]; then
      local port="${BASH_REMATCH[1]}"
      [[ -n "$host_ip" ]] && iptables -A "$SLOT_CHAIN" -d "$host_ip" -p tcp --dport "$port" -j ACCEPT
    fi
  done

  # 项目获准私网放行
  for target in "${PLAN_NETWORK[@]}"; do
    if [[ "$target" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)$ ]]; then
      iptables -A "$SLOT_CHAIN" -d "${BASH_REMATCH[1]}" -p tcp --dport "${BASH_REMATCH[2]}" -j ACCEPT
    elif [[ -n "$target" ]]; then
      iptables -A "$SLOT_CHAIN" -d "$target" -j ACCEPT
    fi
  done

  # 私网网段全拦截 (家庭网段 192.168.0.0/16 默认在此拦截)
  iptables -A "$SLOT_CHAIN" -d 10.0.0.0/8 -j REJECT
  iptables -A "$SLOT_CHAIN" -d 172.16.0.0/12 -j REJECT
  iptables -A "$SLOT_CHAIN" -d 192.168.0.0/16 -j REJECT
  iptables -A "$SLOT_CHAIN" -d 100.64.0.0/10 -j REJECT
  iptables -A "$SLOT_CHAIN" -d 169.254.0.0/16 -j REJECT

  # 放行其余所有公网目标
  iptables -A "$SLOT_CHAIN" -j ACCEPT
}
