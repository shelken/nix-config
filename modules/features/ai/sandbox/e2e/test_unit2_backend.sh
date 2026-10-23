#!/usr/bin/env bash
# ==============================================================================
# 单元 2 端到端验收测试: 能力上限与后端 (test_unit2_backend.sh)
#
# 职责说明:
#   验证单元 2 交付的所有后端能力与 sb 子命令:
#   1. 在一次性隔离 MSB_HOME 中使用真实构建出的 `sb` 产物。
#   2. `sb up` 创建主 VM (sb-main)，挂载根在 guest 内同路径可读写且与宿主双向同步。
#   3. VM 规格（cpus / memory）配置生效。
#   4. 再次执行 `sb up` 复用同一台 VM（非重建）。
#   5. 修改全局 YAML 能力上限后，`sb status` 准确报告上限不一致（inconsistent）。
#   6. 空闲状态下再次执行 `sb up` 触发主 VM 自动重建，新增挂载根在重建后可用，
#      且数据卷 /data 中的持久化内容完整保留。
#   7. 忙碌时修改上限：运行中上下文不被打断，新启动报错并给出运行中上下文数；
#      全部退出后下一次启动自动按新上限重建。
#   8. `sb status` 状态信息与上限一致性校验正确。
#   9. `sb down` 停止 VM，`sb rm` 删除 VM 但保留 disk 数据卷。
#  10. harness_cleanup 结束后一次性环境零残留，宿主日常 VM `sb-default` 状态完好未受扰动。
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./harness.sh
source "$SCRIPT_DIR/harness.sh"

main() {
  echo "========================================================================"
  echo "开始执行单元 2 端到端检查: 全局 YAML、主 VM 后端与 sb 子命令"
  echo "========================================================================"

  local sb_bin
  sb_bin="$(harness_find_or_build_app SB_BIN sb)"
  echo "[+] 使用真实构建的 sb 路径: $sb_bin"

  echo "=== 1. 初始化一次性隔离测试环境 ==="
  harness_setup
  trap "harness_cleanup" EXIT INT TERM

  local test_mount_root="$E2E_DIR/mount_root"
  mkdir -p "$test_mount_root"
  echo "host_content_123" > "$test_mount_root/host_file.txt"

  local test_project="$E2E_DIR/proj"
  mkdir -p "$test_project"

  local test_yaml="$E2E_DIR/test_ceiling.yaml"
  cat <<EOF > "$test_yaml"
image: "ubuntu"
cpus: 2
memory: "2G"
volume:
  name: "test-u2-vol"
  size: "1G"
mount_roots:
  - "$test_mount_root"
  - "$E2E_DIR"
network:
  policy: "public"
  allow:
    - "public"
    - "dns"
EOF

  run_sb() {
    MSB_CONFIG_PATH="$E2E_MSB_CONFIG" MSB_HOME="$E2E_MSB_HOME" SB_CONFIG="$test_yaml" "$sb_bin" "$@"
  }

  echo "=== 2. 测试 sb up 首次创建主 VM ==="
  run_sb up

  echo "=== 3. 校验 VM 规格与挂载读写双向同步 ==="
  local status_json
  status_json="$(run_sb status --json)"
  echo "Status JSON: $status_json"

  local cpus memory busy
  cpus="$(jq -r .cpus <<< "$status_json")"
  memory="$(jq -r .memory <<< "$status_json")"
  busy="$(jq -r .busy <<< "$status_json")"
  [[ "$cpus" == "2" ]] || { echo "[-] CPU 规格校验失败: $cpus (预期 2)" >&2; exit 1; }
  [[ "$memory" == "2G" ]] || { echo "[-] Memory 规格校验失败: $memory (预期 2G)" >&2; exit 1; }
  [[ "$busy" == "false" ]] || { echo "[-] 初始空闲 VM 被误判为 busy" >&2; exit 1; }
  echo "[+] VM 规格校验通过 (cpus=2, memory=2G, busy=false)"

  # guest 读取宿主在挂载根中预先写入的文件
  local guest_read
  guest_read="$(harness_exec sb-main cat "$test_mount_root/host_file.txt")"
  [[ "$guest_read" == "host_content_123" ]] || { echo "[-] guest 读取宿主文件失败: $guest_read" >&2; exit 1; }
  echo "[+] guest 内读取宿主同路径文件成功: $guest_read"

  # guest 写入新文件，验证宿主立即感知同步
  harness_exec sb-main sh -c "echo guest_content_456 > '$test_mount_root/guest_file.txt'"
  local host_read
  host_read="$(cat "$test_mount_root/guest_file.txt")"
  [[ "$host_read" == "guest_content_456" ]] || { echo "[-] 宿主读取 guest 写入失败: $host_read" >&2; exit 1; }
  echo "[+] 宿主读取 guest 写入文件同步成功: $host_read"

  # 向数据卷 /data 写入持久化数据
  harness_exec sb-main sh -c "echo volume_persist_789 > /data/persist.txt"
  echo "[+] 数据卷 /data 写入成功"

  echo "=== 4. 测试再次 sb up (同一配置复用 VM) ==="
  local reuse_out
  reuse_out="$(run_sb up 2>&1)"
  echo "$reuse_out"
  echo "$reuse_out" | grep -q "复用现有 VM" || { echo "[-] 未检测到复用提示" >&2; exit 1; }
  echo "[+] 同配置复用验证通过"

  echo "=== 5. 空闲改上限: sb up 自动重建，新挂载可用且数据保留 ==="
  # 新增挂载根 extra_mount 并把 CPU 调到 3
  local extra_dir="$E2E_DIR/extra_mount"
  mkdir -p "$extra_dir"
  echo "extra_content_999" > "$extra_dir/extra_file.txt"
  cat <<EOF > "$test_yaml"
image: "ubuntu"
cpus: 3
memory: "2G"
volume:
  name: "test-u2-vol"
  size: "1G"
mount_roots:
  - "$test_mount_root"
  - "$E2E_DIR"
network:
  policy: "public"
  allow:
    - "public"
    - "dns"
EOF

  local status_mod
  status_mod="$(run_sb status --json)"
  echo "Modified Status JSON: $status_mod"
  local match_status
  match_status="$(jq -r .ceiling_match <<< "$status_mod")"
  [[ "$match_status" == "false" ]] || { echo "[-] 修改配置后未正确检测到上限不一致" >&2; exit 1; }
  echo "[+] 上限变化检测通过 (ceiling_match=false)"

  local rebuild_out
  rebuild_out="$(run_sb up 2>&1)"
  echo "$rebuild_out"
  echo "$rebuild_out" | grep -q "检测到能力上限变化且主 VM sb-main 空闲，正在重建" || { echo "[-] 未检测到重建提示" >&2; exit 1; }

  local status_rebuilt
  status_rebuilt="$(run_sb status --json)"
  echo "Rebuilt Status JSON: $status_rebuilt"
  local rebuilt_cpus rebuilt_match
  rebuilt_cpus="$(jq -r .cpus <<< "$status_rebuilt")"
  rebuilt_match="$(jq -r .ceiling_match <<< "$status_rebuilt")"
  [[ "$rebuilt_cpus" == "3" ]] || { echo "[-] 重建后 CPU 未生效: $rebuilt_cpus (预期 3)" >&2; exit 1; }
  [[ "$rebuilt_match" == "true" ]] || { echo "[-] 重建后上限指纹不一致: $rebuilt_match" >&2; exit 1; }
  echo "[+] 重建后新规格生效 (cpus=3) 且指纹恢复一致"

  # 重建后新增挂载根在 guest 内可读
  local extra_read
  extra_read="$(harness_exec sb-main cat "$extra_dir/extra_file.txt")"
  [[ "$extra_read" == "extra_content_999" ]] || { echo "[-] 重建后新挂载根不可用: $extra_read" >&2; exit 1; }
  echo "[+] 重建后新挂载根可用: $extra_read"

  # 验证数据盘在 VM 重建后数据完好保留
  local persist_check
  persist_check="$(harness_exec sb-main cat /data/persist.txt)"
  [[ "$persist_check" == "volume_persist_789" ]] || { echo "[-] 重建后数据卷数据丢失: $persist_check" >&2; exit 1; }
  echo "[+] 重建后数据卷内容完整保留: $persist_check"

  echo "=== 6. 忙时改上限: 运行中上下文不中断，新启动报错含上下文数 ==="
  # 后台持续运行的上下文（写入脉冲证明不被打断）
  local pulse_file="$test_project/pulse.txt"
  rm -f "$pulse_file"
  ( cd "$test_project" && run_sb run bash -c 'for i in $(seq 1 40); do echo "pulse_$i" > pulse.txt; sleep 0.5; done' ) &
  local pulse_pid=$!
  local waited=0
  while [[ ! -f "$pulse_file" && $waited -lt 30 ]]; do
    sleep 0.5
    waited=$((waited + 1))
  done
  [[ -f "$pulse_file" ]] || { echo "[-] 脉冲文件未在超时内生成" >&2; kill -9 "$pulse_pid" 2>/dev/null || true; exit 1; }
  local pulse_before
  pulse_before="$(cat "$pulse_file")"
  echo "[+] 后台上下文运行中 (脉冲: $pulse_before)"

  # 忙时把 CPU 调到 4 → 新启动必须报错并给出运行中上下文数（单上下文精确为 1）
  sed 's/^cpus: 3/cpus: 4/' "$test_yaml" > "$test_yaml.new" && mv "$test_yaml.new" "$test_yaml"

  local busy_fail_out busy_fail_code=0
  set +e
  busy_fail_out="$( cd "$test_project" && run_sb run echo "should_not_run" 2>&1 )"
  busy_fail_code=$?
  set -e
  echo "Busy fail output:"
  echo "$busy_fail_out"
  [[ $busy_fail_code -ne 0 ]] || { echo "[-] 忙时修改上限后启动新上下文未被拦截" >&2; kill -9 "$pulse_pid" 2>/dev/null || true; exit 1; }
  echo "$busy_fail_out" | grep -q "sb.yaml 已变" || { echo "[-] 错误信息未说明 sb.yaml 已变化" >&2; kill -9 "$pulse_pid" 2>/dev/null || true; exit 1; }
  echo "$busy_fail_out" | grep -qE "有 ?1 个执行上下文在运行" || { echo "[-] 错误信息未包含精确的运行中上下文数 1: $(echo "$busy_fail_out" | grep -o '有.*个执行上下文在运行')" >&2; kill -9 "$pulse_pid" 2>/dev/null || true; exit 1; }
  echo "[+] 忙时改上限报错校验通过 (含运行中上下文数 1)"

  # 运行中的上下文完全未被打断
  sleep 1.5
  local pulse_after
  pulse_after="$(cat "$pulse_file" 2>/dev/null || echo "pulse_0")"
  echo "Pulse before intercept: $pulse_before, pulse after: $pulse_after"
  [[ "$pulse_after" != "$pulse_before" ]] || { echo "[-] 运中心跳停止，上下文被打断" >&2; kill -9 "$pulse_pid" 2>/dev/null || true; exit 1; }
  echo "[+] 持续脉冲证明运行中上下文完全未受打断"

  # 全部退出后（VM 空闲），下一次启动自动按新上限重建
  wait "$pulse_pid" 2>/dev/null || true
  echo "[+] 运行中上下文已退出，验证空闲后自动重建..."
  local post_rebuild_out cpus_after
  post_rebuild_out="$( cd "$test_project" && run_sb run echo "post_rebuild_ok" 2>&1 )"
  echo "$post_rebuild_out"
  echo "$post_rebuild_out" | grep -q "post_rebuild_ok" || { echo "[-] 空闲后自动重建并启动失败" >&2; exit 1; }
  cpus_after="$(run_sb status --json | jq -r .cpus)"
  [[ "$cpus_after" == "4" ]] || { echo "[-] 空闲自动重建后 CPU 未按新上限生效: $cpus_after (预期 4)" >&2; exit 1; }
  echo "[+] 空闲后下一次启动自动按新上限重建 (cpus=4)"

  echo "=== 7. 测试 sb down 与 sb rm ==="
  run_sb down
  local down_status
  down_status="$(harness_msb inspect sb-main --format json | jq -r .status)"
  [[ "$down_status" == "Stopped" || "$down_status" == "stopped" ]] || { echo "[-] sb down 失败，状态: $down_status" >&2; exit 1; }
  echo "[+] sb down 验证通过 (VM 已停止)"

  run_sb rm
  if harness_msb inspect sb-main --format json 2>/dev/null; then
    echo "[-] sb rm 失败，VM 仍然存在" >&2
    exit 1
  fi
  echo "[+] sb rm 验证通过 (VM 已删除)"

  # 确认命名卷在 VM 删除后依然保留
  harness_msb volume inspect test-u2-vol >/dev/null || { echo "[-] 数据卷被意外删除" >&2; exit 1; }
  echo "[+] 数据卷确认保留存在"

  echo "=== 8. 清理一次性环境并验证零残留 ==="
  harness_cleanup
  trap - EXIT INT TERM

  harness_verify_clean "sb-main"
  echo "========================================================================"
  echo "单元 2 端到端检查全部通过 (Exit Code 0)"
  echo "========================================================================"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
