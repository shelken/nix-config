#!/usr/bin/env bash
# ==============================================================================
# sb：宿主侧 Agent 沙箱管理 CLI
#
# 由 sb.nix 用 writeShellApplication 打包（构建期过 shellcheck）；Nix 只注入
# 下面大写占位符（配置路径、发布目录、launcher 与 guest 查询脚本路径），业务逻辑全部在本文件。
#
# 职责：
#   - 主 VM (sb-main) 的创建、启动、空闲重建、删除
#   - sb sync（宿主写锁 + guest 内 sync-guest.sh）
#   - sb status（规格、指纹一致性、缺失工具）
# ==============================================================================
set -euo pipefail

DEFAULT_MSB_CONFIG="@MSB_CONFIG@"
DEFAULT_MSB_HOME="@MSB_HOME@"
DEFAULT_YAML="@DEFAULT_YAML@"
LAUNCHER="@LAUNCHER@"
GUEST_STATUS="@GUEST_STATUS@"
DEFAULT_SANDBOX_CONFIG="@SANDBOX_CONFIG@"

export MSB_CONFIG_PATH="${MSB_CONFIG_PATH:-$DEFAULT_MSB_CONFIG}"
export MSB_HOME="${MSB_HOME:-$DEFAULT_MSB_HOME}"
# 宿主共用 mise 目录真实路径（ADR 0005）；e2e 通过覆盖它把一次性 VM 挂到 harness 共用目录
export SB_MISE_HOST_DIR="${SB_MISE_HOST_DIR:-/opt/sandbox-mise}"

# ------------------------------------------------------------------
# 主 VM 生命周期锁：跨进程互斥，锁目录固定在 $MSB_HOME/locks，
# 不放在可被删除的 VM 目录 ($MSB_HOME/sandboxes/<vm>) 内。
# 只包住「检查上限指纹 → 必要时重建 → 启动 VM」（ADR 0006 决策 3）。
# ------------------------------------------------------------------
SB_LOCK_DIR="$MSB_HOME/locks"
mkdir -p "$SB_LOCK_DIR"

# 获取主 VM 生命周期互斥锁：acquire_sb_lock [timeout_s]
# 成功后锁 fd 持有至 release_sb_lock 或进程退出；失败（超时）返回非 0，
# 调用方必须放弃本次清理/重建，不得继续删除。
acquire_sb_lock() {
  local timeout_s="${1:-300}"
  local lock_file="$SB_LOCK_DIR/sb-main.lock"
  exec 8>>"$lock_file"
  if ! flock -w "$timeout_s" 8; then
    exec 8>&-
    echo "[-] 错误: 获取生命周期锁超时 (${timeout_s}s): ${lock_file}，本次操作放弃" >&2
    return 1
  fi
}

release_sb_lock() {
  flock -u 8 2>/dev/null || true
  # 只关闭锁 fd：exec 的 2>/dev/null 会永久重定向当前 shell 的 stderr
  exec 8>&-
}

YAML_FILE="${SB_CONFIG:-}"
if [[ -z "$YAML_FILE" ]]; then
  if [[ -f "$HOME/.config/sandbox/sb.yaml" ]]; then
    YAML_FILE="$HOME/.config/sandbox/sb.yaml"
  else
    YAML_FILE="$DEFAULT_YAML"
  fi
fi

# 寻找 msb 可执行文件
find_msb() {
  if command -v msb >/dev/null 2>&1; then
    echo "msb"
  elif [[ -x "$HOME/.local/share/mise/installs/microsandbox/0.7.7/msb" ]]; then
    echo "$HOME/.local/share/mise/installs/microsandbox/0.7.7/msb"
  elif [[ -x "/run/current-system/sw/bin/msb" ]]; then
    echo "/run/current-system/sw/bin/msb"
  else
    echo "[-] 错误: 未能在 PATH 或 mise 目录找到 msb 0.7.7" >&2
    exit 1
  fi
}

MSB="$(find_msb)"

# sec-run 包装判定：sb 在宿主侧启动 msb 时自动注入 sops 凭据（GITHUB_TOKEN 等）。
# e2e/CI 用假凭据验证「无有效 token → 私有插件跳过」路径时必须能关闭注入，
# 否则宿主真实凭据会让假测失效；SB_NO_HOST_CREDENTIALS=1 显式禁用。
if command -v sec-run >/dev/null 2>&1 && [[ "${SB_NO_HOST_CREDENTIALS:-0}" != "1" ]]; then
  SEC_RUN=(sec-run)
else
  SEC_RUN=()
fi

run_msb() {
  if [[ ${#SEC_RUN[@]} -gt 0 ]]; then
    "${SEC_RUN[@]}" "$MSB" "$@"
  else
    "$MSB" "$@"
  fi
}

usage() {
  cat <<'EOF'
用法:
sb up                创建或启动主 VM (sb-main)，已运行且上限一致则复用，上限变化且空闲则重建
sb down              停止主 VM
sb rm [--force]       删除主 VM，保留数据卷；有运行中上下文时拒绝，--force 强制删除
sb sync              补齐沙箱内的 mise 工具与 OMP 插件 (幂等，只装缺失项；宿主写锁串行化)
sb status [--json]   查看主 VM 状态、规格、能力上限指纹一致性与缺失工具
sb run [-t] CMD…     在当前项目执行上下文内运行命令 (TTY 自适应)
sb shell             进入当前项目执行上下文的交互式 Bash shell
sb volume …          命名卷管理 (原生透传至 msb volume)
EOF
  exit "${1:-0}"
}

# 展开路径里的 ~、$HOME、${HOME} 前缀/引用（不引入 eval；realpath 与相对根解析由调用点负责）
expand_path() {
  local p="$1" home="$HOME"
  # shellcheck disable=SC2016  # 刻意保持字面量，交给下面的参数展开匹配
  local brace_home='${HOME}' plain_home='$HOME'
  p="${p/#\~/$home}"
  # 先展开 ${HOME}（花括号形式更长）再展开 $HOME，避免后者把前者的前缀拆坏
  p="${p//$brace_home/$home}"
  p="${p//$plain_home/$home}"
  printf '%s\n' "$p"
}

# 从全局 YAML 声明转换为 msb 所需的配置 JSON
generate_msb_config() {
  local src_yaml="$1"
  local dst_json="$2"

  if [[ ! -f "$src_yaml" ]]; then
    echo "[-] 错误: 找不到全局能力上限配置文件: $src_yaml" >&2
    return 1
  fi

  local raw_json
  raw_json="$(yq -o=json '.' "$src_yaml")"

  local image cpus memory vol_name
  image="$(jq -r '.image // .vm.image // "ubuntu"' <<< "$raw_json")"
  cpus="$(jq -r '.cpus // .vm.cpus // 4' <<< "$raw_json")"
  memory="$(jq -r '.memory // .vm.memory // "8G"' <<< "$raw_json")"
  vol_name="$(jq -r '.volume.name // "sb-main-data"' <<< "$raw_json")"
  local -a roots=()
  while IFS= read -r root_path; do
    [[ -n "$root_path" ]] || continue
    local expanded
    expanded="$(expand_path "$root_path")"
    if [[ ! -e "$expanded" ]]; then
      mkdir -p "$expanded"
    fi
    local real
    real="$(realpath "$expanded")"
    roots+=("$real")
  done < <(jq -r '(.mount_roots // [])[]' <<< "$raw_json")

  local roots_json
  if [[ ${#roots[@]} -gt 0 ]]; then
    roots_json="$(printf '%s\n' "${roots[@]}" | jq -R . | jq -s .)"
  else
    roots_json="[]"
  fi

  # 配置发布源优先级：显式覆盖 > 宿主持久发布目录 > 内置 store 目录
  # 持久目录在更新 current 链接时保持路径不变，内容变化（模型、提示词、工具清单）
  # 因此不会改变上限指纹；直接挂 store 路径会让每次配置发布都触发重建。
  local real_sandbox_cfg=""
  if [[ -n "${SB_SANDBOX_CONFIG:-}" && -d "${SB_SANDBOX_CONFIG:-}" ]]; then
    real_sandbox_cfg="$(realpath "$SB_SANDBOX_CONFIG")"
  elif [[ -d "$HOME/.config/sandbox/current" ]]; then
    real_sandbox_cfg="$(realpath "$HOME/.config/sandbox")"
  elif [[ -n "$DEFAULT_SANDBOX_CONFIG" && -d "$DEFAULT_SANDBOX_CONFIG" ]]; then
    real_sandbox_cfg="$(realpath "$DEFAULT_SANDBOX_CONFIG")"
  elif [[ -d "$HOME/.config/sandbox" ]]; then
    real_sandbox_cfg="$(realpath "$HOME/.config/sandbox")"
  fi

  local -a sb_mount_entries=()
  if [[ -n "$real_sandbox_cfg" && -d "$real_sandbox_cfg" ]]; then
    if [[ -d "$real_sandbox_cfg/current" ]]; then
      sb_mount_entries+=("$real_sandbox_cfg:/run/sandbox-config:ro,stat-virt=relaxed")
    else
      sb_mount_entries+=("$real_sandbox_cfg:/run/sandbox-config/current:ro,stat-virt=relaxed")
    fi
  fi
  local sb_mount_json
  if [[ ${#sb_mount_entries[@]} -gt 0 ]]; then
    sb_mount_json="$(printf '%s\n' "${sb_mount_entries[@]}" | jq -R . | jq -s .)"
  else
    sb_mount_json="[]"
  fi

  # 宿主共用 mise 目录（ADR 0005）：挂进主 VM，guest 路径固定 /opt/sandbox-mise。
  # 上限指纹只含 guest 路径与读写属性，不含宿主真实路径。
  # 宿主真实路径默认取环境变量 SB_MISE_HOST_DIR（由 default.nix 统一注入），
  # e2e 一次性 VM 通过覆盖它指向 harness 共用目录，同样实现全 VM 共用。
  local mise_real="${SB_MISE_HOST_DIR:-/opt/sandbox-mise}"
  if [[ ! -d "$mise_real" ]]; then
    echo "[-] 错误: 宿主共用 mise 目录不存在: $mise_real (可通过 SB_MISE_HOST_DIR 覆盖)" >&2
    return 1
  fi
  mise_real="$(realpath "$mise_real")"
  local sb_mise_json
  sb_mise_json="$(printf '%s\n' "$mise_real:/opt/sandbox-mise:rw" | jq -R . | jq -s .)"
  # 供 get_config_fingerprint 在计算指纹时识别并规范化该挂载条目
  SB_MISE_HOST_DIR_REAL="$mise_real"

  local network_json
  network_json="$(jq -c '.network // {"policy": "public", "allow": ["public", "dns"]}' <<< "$raw_json")"

  local secrets_json
  secrets_json="$(jq -c '.secrets // {}' <<< "$raw_json")"

  jq -n \
    --arg img "$image" \
    --argjson cpus "$cpus" \
    --arg mem "$memory" \
    --arg vol "$vol_name" \
    --arg nix "/nix/store:/nix/store:ro,stat-virt=relaxed" \
    --arg sb_cfg "$real_sandbox_cfg" \
    --argjson sb_mounts "$sb_mount_json" \
    --argjson sb_mise "$sb_mise_json" \
    --argjson roots "$roots_json" \
    --argjson net "$network_json" \
    --argjson sec "$secrets_json" \
    '
    (
      [{"named": $vol, "target": "/data"}, $nix]
      + $sb_mounts
      + $sb_mise
      + ($roots | map("\(.):\(.)"))
    ) as $mounts |
    (
      if ($sb_cfg | length) > 0 then [
        {"symlink": {"target": "/run/sandbox-config/current/.agents", "link": "/root/.agents"}}
      ] else null end
    ) as $patches |
    {
      image: $img,
      cpus: $cpus,
      memory: $mem,
      mounts: $mounts,
      network: $net
    }
    + (if $patches != null then {patches: $patches} else {} end)
    + (if ($sec | keys | length) > 0 then {secrets: $sec} else {} end)
    ' > "$dst_json"
}

# 计算上限指纹：先在副本里把共用 mise 挂载的宿主源路径规范化为固定占位值，
# 再对 canonical JSON 做哈希 —— 实际 VM 配置仍使用真实路径（ADR 0005 决策 2）。
get_config_fingerprint() {
  local conf_file="$1"
  jq -S -c --arg mise_mount "$SB_MISE_HOST_DIR_REAL:/opt/sandbox-mise:rw" '
    .mounts |= map(if . == $mise_mount then "__SB_MISE_HOST__:/opt/sandbox-mise:rw" else . end)
  ' "$conf_file" | sha256sum | cut -d' ' -f1
}

wait_for_vm_running() {
  local vm_name="$1"
  local max_attempts=30
  local attempt=0
  while [[ $attempt -lt $max_attempts ]]; do
    local st
    st="$("$MSB" inspect "$vm_name" --format json 2>/dev/null | jq -r '.status // empty' 2>/dev/null || true)"
    if [[ "$st" == "Running" ]]; then
      return 0
    fi
    sleep 0.5
    attempt=$((attempt + 1))
  done
  echo "[-] 错误: 等待 VM $vm_name 达到 Running 状态超时" >&2
  return 1
}

# 判定主 VM 是否有运行中的执行上下文：忙闲只看 guest 内 launcher 的登记表（ADR 0006 决策 3）
is_vm_busy() {
  local vm_name="$1"
  local st
  st="$("$MSB" inspect "$vm_name" --format json 2>/dev/null | jq -r '.status // empty' 2>/dev/null || true)"
  if [[ "$st" != "Running" ]]; then
    return 1
  fi

  # 通过 guest 内 launcher 检查活跃上下文登记（自动清扫死进程残留）
  local active_count
  active_count="$("$MSB" exec "$vm_name" -- bash "$LAUNCHER" --check-busy 2>/dev/null || echo "")"
  if [[ "$active_count" =~ ^[0-9]+$ ]]; then
    [[ "$active_count" -gt 0 ]] && return 0
    return 1
  fi

  # 容错降级：若 launcher 尚未就绪，检查宿主连接与 guest 进程
  if pgrep -fl "msb exec.*${vm_name}" >/dev/null 2>&1; then
    return 0
  fi
  if "$MSB" exec "$vm_name" -- sh -c 'pgrep -x omp || pgrep -x bwrap' >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# 查询 guest 内缺失的 mise 工具（ADR 0006 决策 5：不报告插件安装状态）。
# guest 侧脚本独立成 guest-status.sh（只输出 TSV），JSON 组装在这里做，避免多层引号嵌套。
# 查询失败必须报错而不是伪装成全齐：返回非零并打印原因。
query_guest_tool_state() {
  local vm_name="$1"
  local out rc=0
  out="$("$MSB" exec "$vm_name" -- bash "$GUEST_STATUS" 2>/dev/null)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "[-] 错误: 查询 $vm_name 缺失工具失败 (rc=$rc)" >&2
    return 1
  fi
  # 宿主侧组装 JSON：空输出 → {"missing":[]}
  if [[ -z "$out" ]]; then
    printf '%s\n' '{"missing":[]}'
    return 0
  fi
  printf '%s\n' "$out" | jq -R -s -c '
    split("\n") | map(select(length > 0) | split("\t")) as $rows
    | {missing: [$rows[] | select(.[0] == "missing") | .[1]]}'
}

# 在 guest 内执行 sync-guest.sh
exec_sync_guest() {
  local vm_name="$1"
  shift
  run_msb exec "$vm_name" --stream -- bash -c '
    if [[ -f /run/sandbox-config/current/sync-guest.sh ]]; then
      exec bash /run/sandbox-config/current/sync-guest.sh "$@"
    elif [[ -f /run/sandbox-config/sync-guest.sh ]]; then
      exec bash /run/sandbox-config/sync-guest.sh "$@"
    else
      echo "[!] 警告: 未在沙箱内找到 sync-guest.sh，跳过自动补齐" >&2
      exit 1
    fi
  ' argv0 "$@"
}

# 获取共用 mise 写锁后执行 sync（调用前必须已持有主 VM 生命周期锁）。
# 锁目录固定在共用 mise 层根目录，跨 VM 串行化所有对安装层的写入（ADR 0005 决策 6）。
run_sync_with_mise_lock() {
  local vm_name="$1"
  shift
  local lock_dir="${SB_MISE_LOCK_DIR:-$HOME/Data/sandboxes/mise/aarch64-linux}"
  mkdir -p "$lock_dir"
  local lock_file="$lock_dir/.sync.lock"
  exec 9>"$lock_file"
  if ! flock -w 600 9; then
    echo "[-] 错误: 获取共用 mise 目录写锁超时 (600s): $lock_file" >&2
    return 1
  fi
  exec_sync_guest "$vm_name" "$@"
  local rc=$?
  exec 9>&-
  return $rc
}

# sb sync 入口：必要时先在生命周期锁内确保 VM 就绪，再持共用 mise 写锁补齐（只补缺，无需判忙闲）
sb_sync() {
  local vm_name="sb-main"
  if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
    vm_name="$1"
    shift
  fi
  if ! "$MSB" inspect "$vm_name" --format json >/dev/null 2>&1; then
    echo "[sb] VM $vm_name 尚未创建，正在自动启动..." >&2
    if ! acquire_sb_lock 300; then
      echo "[-] 错误: 主 VM 生命周期锁被其他进程长期持有，放弃本次启动" >&2
      exit 1
    fi
    ensure_vm_locked
    release_sb_lock
  elif [[ "$("$MSB" inspect "$vm_name" --format json 2>/dev/null | jq -r '.status // empty' 2>/dev/null || true)" != "Running" ]]; then
    echo "[sb] VM $vm_name 处于停止状态，正在启动..." >&2
    if ! acquire_sb_lock 300; then
      echo "[-] 错误: 主 VM 生命周期锁被其他进程长期持有，放弃本次启动" >&2
      exit 1
    fi
    run_msb start "$vm_name"
    wait_for_vm_running "$vm_name"
    release_sb_lock
  fi
  echo "[sb] 正在沙箱 $vm_name 内执行工具与插件补齐 (sb sync)..." >&2
  run_sync_with_mise_lock "$vm_name" "$@"
}

# 确保 VM 已按当前能力上限启动（调用前必须已持有 sb-main.lock）
ensure_vm_locked() {
  local vm_name="sb-main"
  local yaml_file="$YAML_FILE"

  local tmp_cfg
  tmp_cfg="$(mktemp "/tmp/sb-${vm_name}-XXXXXX.json")"
  # shellcheck disable=SC2064  # 需要展开当前 tmp_cfg
  trap "rm -f '$tmp_cfg'" EXIT INT TERM

  generate_msb_config "$yaml_file" "$tmp_cfg"
  local current_fp
  current_fp="$(get_config_fingerprint "$tmp_cfg")"

  local ceiling_json vol_name vol_size
  ceiling_json="$(yq -o=json '.' "$yaml_file")"
  vol_name="$(jq -r '.volume.name // "sb-main-data"' <<< "$ceiling_json")"
  vol_size="$(jq -r '.volume.size // "8G"' <<< "$ceiling_json")"

  # 确保数据卷卷存在（删除 VM 时保留，重新挂载即持久数据）
  if ! "$MSB" volume inspect "$vol_name" >/dev/null 2>&1; then
    echo "[sb] 数据卷 $vol_name 不存在，正在创建 (ext4 disk, 大小: $vol_size)..." >&2
    "$MSB" volume create "$vol_name" --kind disk --size "$vol_size" >&2
  fi

  # VM 创建后要落的状态：指纹与上限 YAML，供指纹比对与诊断
  record_vm_state() {
    mkdir -p "$MSB_HOME/sandboxes/$vm_name"
    echo "$current_fp" > "$MSB_HOME/sandboxes/$vm_name/ceiling.hash"
    cp "$yaml_file" "$MSB_HOME/sandboxes/$vm_name/ceiling.yaml"
  }

  local -a create_args=(--name "$vm_name" --conf "$tmp_cfg" --label "ceiling_fingerprint=$current_fp")

  if vm_state="$("$MSB" inspect "$vm_name" --format json 2>/dev/null)"; then
    local vm_status vm_fp
    vm_status="$(jq -r '.status // empty' <<< "$vm_state")"
    vm_fp="$(jq -r '.config.labels.ceiling_fingerprint // empty' <<< "$vm_state")"
    if [[ -z "$vm_fp" && -f "$MSB_HOME/sandboxes/$vm_name/ceiling.hash" ]]; then
      vm_fp="$(cat "$MSB_HOME/sandboxes/$vm_name/ceiling.hash")"
    fi

    if [[ "$vm_fp" == "$current_fp" ]]; then
      if [[ "$vm_status" == "Running" ]]; then
        echo "[sb] 主 VM $vm_name 正在运行且能力上限一致，复用现有 VM" >&2
      else
        echo "[sb] 主 VM $vm_name 已存在但处于停止状态，正在启动..." >&2
        run_msb start "$vm_name" >&2
        wait_for_vm_running "$vm_name"
        echo "[sb] 主 VM $vm_name 启动成功" >&2
      fi
    else
      # 上限发生变化；锁内重读忙碌状态（ADR 0006 决策 2）：
      # 空闲 → 直接重建；忙 → 只报错并给出运行中上下文数，不登记任何状态
      if is_vm_busy "$vm_name"; then
        local active_count
        active_count="$("$MSB" exec "$vm_name" -- bash "$LAUNCHER" --check-busy 2>/dev/null || echo "?")"
        echo "[-] 错误: sb.yaml 已变，主 VM 有 ${active_count} 个执行上下文在运行，全部退出后再启动即按新上限重建。" >&2
        exit 1
      fi
      echo "[sb] 检测到能力上限变化且主 VM $vm_name 空闲，正在重建 (保留数据盘 $vol_name)..." >&2
      "$MSB" stop "$vm_name" >/dev/null 2>&1 || true
      "$MSB" rm --force "$vm_name" >/dev/null 2>&1 || true
      run_msb create "${create_args[@]}" >&2
      record_vm_state
      wait_for_vm_running "$vm_name"
      echo "[sb] 主 VM $vm_name 重建完成并已启动" >&2
    fi
  else
    echo "[sb] 正在创建主 VM: $vm_name (上限指纹: ${current_fp:0:12})..." >&2
    run_msb create "${create_args[@]}" >&2
    record_vm_state
    wait_for_vm_running "$vm_name"
    echo "[sb] 主 VM $vm_name 创建并启动成功" >&2
    # 首次创建自动补齐一次工具（ADR 0005 决策 8）；已持有生命周期锁，只补共用 mise 写锁
    echo "[sb] 首次创建自动执行 sb sync 补齐工具..." >&2
    run_sync_with_mise_lock "$vm_name" >&2 || echo "[sb] 首次工具自动补齐未全部完成 (可稍后通过 sb sync 补齐)" >&2
  fi

  rm -f "$tmp_cfg"
  trap - EXIT INT TERM
}

# sb up：生命周期锁内的 ensure（只保证 VM 就绪）
sb_up() {
  if ! acquire_sb_lock 300; then
    echo "[-] 错误: 主 VM sb-main 生命周期锁被其他进程长期持有，放弃本次启动/重建" >&2
    exit 1
  fi
  ensure_vm_locked
  release_sb_lock
}

# 解析项目执行计划并严格校验能力上限 (项目根、worktree common dir、.sandbox.yaml)
resolve_and_validate_plan() {
  local cwd="$1"
  local ceiling_yaml="$2"

  local ceiling_json
  ceiling_json="$(yq -o=json '.' "$ceiling_yaml")"

  # 1. 展开并规范化能力上限中的 mount_roots
  local -a allowed_roots=()
  while IFS= read -r root_path; do
    [[ -n "$root_path" ]] || continue
    local expanded
    expanded="$(expand_path "$root_path")"
    if [[ -d "$expanded" ]]; then
      allowed_roots+=("$(realpath "$expanded")")
    fi
  done < <(jq -r '(.mount_roots // [])[]' <<< "$ceiling_json")

  # 2. 定位项目根 project_root
  local project_root=""
  if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    project_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  if [[ -z "$project_root" ]]; then
    project_root="$cwd"
  fi
  project_root="$(realpath "$project_root")"

  # 校验 project_root 是否落在挂载根内
  local root_allowed=0
  for ar in "${allowed_roots[@]}"; do
    if [[ "$project_root" == "$ar" || "$project_root" == "$ar"/* ]]; then
      root_allowed=1
      break
    fi
  done
  if [[ "$root_allowed" -eq 0 ]]; then
    echo "[-] 错误: 当前项目根目录 $project_root 超出沙箱能力上限 (未落在 sb.yaml mount_roots 挂载根内)" >&2
    return 1
  fi

  # 3. Worktree 自动加绑 git common dir；不在挂载根内时无法透传给 guest，
  # 必须显式报错而不是让 launcher 静默跳过绑定（上下文内 git 丢历史）
  local git_common_dir=""
  if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local cd_raw
    cd_raw="$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null || true)"
    if [[ -n "$cd_raw" ]]; then
      git_common_dir="$(cd "$cwd" && realpath "$cd_raw")"
    fi
  fi
  if [[ -n "$git_common_dir" && "$git_common_dir" != "$project_root" && "$git_common_dir" != "$project_root"/* ]]; then
    local gcd_allowed=0
    for ar in "${allowed_roots[@]}"; do
      if [[ "$git_common_dir" == "$ar" || "$git_common_dir" == "$ar"/* ]]; then
        gcd_allowed=1
        break
      fi
    done
    if [[ "$gcd_allowed" -eq 0 ]]; then
      echo "[-] 错误: worktree 的 git common dir $git_common_dir 超出沙箱能力上限 (未落在 sb.yaml mount_roots 挂载根内)，上下文内 git 将丢失历史，请先把该路径加入 mount_roots" >&2
      return 1
    fi
  fi

  # 4. 解析与校验 .sandbox.yaml
  local proj_cfg="$project_root/.sandbox.yaml"
  local imports_json="[]"
  local network_json="[]"
  local paths_json="[]"

  if [[ -f "$proj_cfg" ]]; then
    local cfg_json
    cfg_json="$(yq -o=json '.' "$proj_cfg")"

    # 4a. 校验 imports
    local -a verified_imports=()
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      local src dest
      if jq -e 'type == "string"' <<< "$item" >/dev/null 2>&1; then
        src="$(jq -r . <<< "$item")"
        dest="$(basename "$src")"
      else
        src="$(jq -r '.src // .path' <<< "$item")"
        dest="$(jq -r '.dest // .dst // .name // empty' <<< "$item")"
        if [[ -z "$dest" ]]; then dest="$(basename "$src")"; else dest="$(basename "$dest")"; fi
      fi

      src="${src/#\~/$HOME}"
      if [[ "$src" != /* ]]; then
        src="$project_root/$src"
      fi
      if [[ ! -f "$src" ]]; then
        echo "[-] 错误: .sandbox.yaml 中声明的导入文件不存在: $src" >&2
        return 1
      fi
      local real_src
      real_src="$(realpath "$src")"
      verified_imports+=("$(jq -n --arg src "$real_src" --arg dest "$dest" '{src: $src, dest: $dest}')")
    done < <(jq -c '.imports[]? // empty' <<< "$cfg_json")

    if [[ ${#verified_imports[@]} -gt 0 ]]; then
      imports_json="$(printf '%s\n' "${verified_imports[@]}" | jq -s .)"
    fi

    # 4b. 校验 network
    local -a allowed_net_targets=()
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      allowed_net_targets+=("$item")
    done < <(jq -r '.network.allow[]? // empty' <<< "$ceiling_json")

    local -a verified_network=()
    while IFS= read -r net_target; do
      [[ -n "$net_target" ]] || continue
      local target_allowed=0
      local target_ip="${net_target%:*}"
      for an in "${allowed_net_targets[@]}"; do
        if [[ "$net_target" == "$an" || "$target_ip" == "$an" ]]; then
          target_allowed=1
          break
        fi
      done
      if [[ "$target_allowed" -eq 0 ]]; then
        echo "[-] 错误: .sandbox.yaml 中声明的私网目标 $net_target 超出能力上限 (sb.yaml network.allow 未授权该目标)" >&2
        return 1
      fi
      verified_network+=("$net_target")
    done < <(jq -r '.network[]? // empty' <<< "$cfg_json")

    if [[ ${#verified_network[@]} -gt 0 ]]; then
      network_json="$(printf '%s\n' "${verified_network[@]}" | jq -R . | jq -s .)"
    fi

    # 4c. 校验 paths
    local -a verified_paths=()
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      local p ro="false"
      if jq -e 'type == "string"' <<< "$item" >/dev/null 2>&1; then
        local raw_p
        raw_p="$(jq -r . <<< "$item")"
        if [[ "$raw_p" == *:ro ]]; then
          p="${raw_p%:ro}"
          ro="true"
        else
          p="$raw_p"
        fi
      else
        p="$(jq -r '.path // empty' <<< "$item")"
        if jq -e '.readonly == true or .ro == true' <<< "$item" >/dev/null 2>&1; then
          ro="true"
        fi
      fi

      p="${p/#\~/$HOME}"
      if [[ "$p" != /* ]]; then
        p="$project_root/$p"
      fi
      if [[ ! -e "$p" ]]; then
        echo "[-] 错误: .sandbox.yaml 中声明的额外路径不存在: $p" >&2
        return 1
      fi
      local real_p
      real_p="$(realpath "$p")"

      local p_allowed=0
      for ar in "${allowed_roots[@]}"; do
        if [[ "$real_p" == "$ar" || "$real_p" == "$ar"/* ]]; then
          p_allowed=1
          break
        fi
      done
      if [[ "$p_allowed" -eq 0 ]]; then
        echo "[-] 错误: .sandbox.yaml 中声明的额外路径 $real_p 超出能力上限 (未落在 sb.yaml mount_roots 挂载根内)" >&2
        return 1
      fi

      verified_paths+=("$(jq -n --arg path "$real_p" --argjson ro "$ro" '{path: $path, readonly: $ro}')")
    done < <(jq -c '.paths[]? // empty' <<< "$cfg_json")

    if [[ ${#verified_paths[@]} -gt 0 ]]; then
      paths_json="$(printf '%s\n' "${verified_paths[@]}" | jq -s .)"
    fi
  fi

  # 5. 提取默认授权目标 default_allow (非家庭网段项目，如 host:tcp:*)
  local default_allow_json
  default_allow_json="$(jq -c '[.network.allow[]? | select(. | test("^host:tcp:"))]' <<< "$ceiling_json")"

  # 6. 生成最终计划 JSON
  jq -n \
    --arg pr "$project_root" \
    --arg gcd "$git_common_dir" \
    --arg cwd "$cwd" \
    --argjson imp "$imports_json" \
    --argjson net "$network_json" \
    --argjson paths "$paths_json" \
    --argjson def_allow "$default_allow_json" \
    '{
      project_root: $pr,
      git_common_dir: $gcd,
      cwd: $cwd,
      imports: $imp,
      network: $net,
      paths: $paths,
      default_allow: $def_allow
    }'
}

cmd="${1:-}"
shift || true

case "$cmd" in
  up)
    sb_up
    ;;

  down)
    # 停止操作与创建/启动/重建互斥（同一把生命周期锁）
    if ! acquire_sb_lock 300; then
      echo "[-] 错误: 主 VM sb-main 生命周期锁被其他进程长期持有，放弃本次停止" >&2
      exit 1
    fi
    echo "[sb] 正在停止主 VM sb-main..." >&2
    "$MSB" stop sb-main "$@"
    release_sb_lock
    ;;

  rm)
    force=0
    declare -a rm_args=()
    for arg in "$@"; do
      if [[ "$arg" == "--force" || "$arg" == "-f" ]]; then
        force=1
      else
        rm_args+=("$arg")
      fi
    done
    # 删除操作与创建/启动/重建互斥（同一把生命周期锁）
    if ! acquire_sb_lock 300; then
      echo "[-] 错误: 主 VM sb-main 生命周期锁被其他进程长期持有，放弃本次删除" >&2
      exit 1
    fi
    # 有运行中的执行上下文时拒绝直接删除，--force 才强制（避免一键打断所有 Agent）
    if [[ "$force" -eq 0 ]] && is_vm_busy sb-main; then
      active_count="$("$MSB" exec sb-main -- bash "$LAUNCHER" --check-busy 2>/dev/null || echo "?")"
      echo "[-] 错误: 主 VM sb-main 有 ${active_count} 个执行上下文正在运行，拒绝删除。全部退出后重试，或用 sb rm --force 强制 (会打断所有上下文)" >&2
      exit 1
    fi
    echo "[sb] 正在删除主 VM sb-main (保留数据卷)..." >&2
    rm -f "$MSB_HOME/sandboxes/sb-main/ceiling.hash" 2>/dev/null || true
    "$MSB" rm --force sb-main "${rm_args[@]}"
    release_sb_lock
    ;;

  status)
    json_mode=0
    for arg in "$@"; do
      if [[ "$arg" == "--json" || "$arg" == "-j" ]]; then
        json_mode=1
      fi
    done

    vm_name="sb-main"
    status="Not created"
    cpus="-"
    memory="-"
    vm_fp="-"
    current_fp="-"
    ceiling_match="not_created"
    busy="idle"

    if vm_state="$("$MSB" inspect "$vm_name" --format json 2>/dev/null)"; then
      status="$(jq -r '.status // empty' <<< "$vm_state")"
      cpus="$(jq -r '.active_config.resources.cpus // .config.resources.cpus // "-"' <<< "$vm_state")"
      mem_mib="$(jq -r '.active_config.resources.memory_mib // .config.resources.memory_mib // "-"' <<< "$vm_state")"
      if [[ "$mem_mib" =~ ^[0-9]+$ ]]; then
        if (( mem_mib % 1024 == 0 )); then
          memory="$((mem_mib / 1024))G"
        else
          memory="${mem_mib}M"
        fi
      else
        memory="$mem_mib"
      fi

      vm_fp="$(jq -r '.config.labels.ceiling_fingerprint // empty' <<< "$vm_state")"
      if [[ -z "$vm_fp" && -f "$MSB_HOME/sandboxes/$vm_name/ceiling.hash" ]]; then
        vm_fp="$(cat "$MSB_HOME/sandboxes/$vm_name/ceiling.hash")"
      fi
      if [[ -z "$vm_fp" ]]; then
        vm_fp="-"
      fi
      if is_vm_busy "$vm_name"; then
        busy="busy"
      fi
    fi

    if [[ -f "$YAML_FILE" ]]; then
      tmp_cfg="$(mktemp /tmp/sb-status-XXXXXX.json)"
      if generate_msb_config "$YAML_FILE" "$tmp_cfg" 2>/dev/null; then
        current_fp="$(get_config_fingerprint "$tmp_cfg")"
      fi
      rm -f "$tmp_cfg"
    fi

    if [[ "$status" == "Not created" ]]; then
      ceiling_match="not_created"
    elif [[ "$vm_fp" != "-" && "$vm_fp" == "$current_fp" ]]; then
      ceiling_match="consistent"
    else
      ceiling_match="inconsistent"
    fi

    # 只报告缺失的 mise 工具（ADR 0006 决策 5）
    missing_tools_json="[]"
    missing_tools_str="无"
    if [[ "$status" == "Running" ]]; then
      guest_state="$(query_guest_tool_state "$vm_name")"
      if jq -e 'type == "object" and has("missing")' <<< "$guest_state" >/dev/null 2>&1; then
        missing_tools_json="$(jq -c '.missing' <<< "$guest_state")"
        if [[ "$(jq 'length' <<< "$missing_tools_json")" -gt 0 ]]; then
          missing_tools_str="$(jq -r 'join(", ")' <<< "$missing_tools_json")"
        fi
      fi
    elif [[ "$status" == "Not created" ]]; then
      missing_tools_str="-"
    else
      missing_tools_str="未知 (VM 未运行)"
    fi

    if [[ "$json_mode" -eq 1 ]]; then
      jq -n \
        --arg name "$vm_name" \
        --arg status "$status" \
        --arg cpus "$cpus" \
        --arg memory "$memory" \
        --arg vm_fingerprint "$vm_fp" \
        --arg current_fingerprint "$current_fp" \
        --arg ceiling_match "$ceiling_match" \
        --arg busy "$busy" \
        --argjson missing_tools "$missing_tools_json" \
        '{
          name: $name,
          status: $status,
          cpus: $cpus,
          memory: $memory,
          vm_fingerprint: $vm_fingerprint,
          current_fingerprint: $current_fingerprint,
          ceiling_match: ($ceiling_match == "consistent"),
          ceiling_status: $ceiling_match,
          busy: ($busy == "busy"),
          missing_tools: $missing_tools
        }'
    else
      cat <<EOF
VM 名称: $vm_name
VM 状态: $status
VM 规格: cpus=$cpus, memory=$memory
运行指纹: $vm_fp
当前指纹: $current_fp
上限一致: $ceiling_match
运行状态: $busy
缺失工具: $missing_tools_str
EOF
    fi
    ;;

  sync)
    sb_sync "$@"
    ;;

  volume)
    exec "$MSB" volume "$@"
    ;;

  run)
    terminal=(--stream)
    if [[ -t 0 && -t 1 ]]; then
      terminal=(-t)
    fi

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t)
          terminal=(-t)
          shift
          ;;
        --)
          shift
          break
          ;;
        *)
          break
          ;;
      esac
    done

    if [[ $# -eq 0 ]]; then
      echo "[-] 错误: sb run 需要提供待执行的命令。示例: sb run git status" >&2
      exit 1
    fi

    current_cwd="$(pwd -P)"
    plan_json="$(resolve_and_validate_plan "$current_cwd" "$YAML_FILE")"
    project_root="$(jq -r '.project_root' <<< "$plan_json")"
    ctx_id="ctx_$(date +%s)_$RANDOM"

    # 生命周期锁包住「检查指纹 → 必要时重建 → 启动 VM」，之后进入 launcher
    if ! acquire_sb_lock 300; then
      echo "[-] 错误: 主 VM sb-main 生命周期锁被其他进程长期持有，放弃本次启动" >&2
      exit 1
    fi
    ensure_vm_locked
    release_sb_lock

    # 复制导入文件（若声明）：先在 guest 登记「启动中」标记，宽限期内清扫与忙碌计数
    # 都视该目录为占用（凭据复制窗口不被并发启动误删）；复制失败或宿主中断时由
    # trap 回收整个上下文目录，凭据不在 guest 残留
    imports_count="$(jq -r '.imports | length' <<< "$plan_json")"
    ctx_guest_dir="/run/sandbox/contexts/$ctx_id"
    if [[ "$imports_count" -gt 0 ]]; then
      run_msb exec sb-main -- bash -c "mkdir -p '$ctx_guest_dir/imports' && touch '$ctx_guest_dir/starting'"
      # shellcheck disable=SC2329  # 仅经 trap 间接调用
      host_reclaim_ctx() {
        run_msb exec sb-main -- rm -rf "$ctx_guest_dir" 2>/dev/null || true
      }
      trap host_reclaim_ctx EXIT INT TERM HUP
      while IFS= read -r imp; do
        [[ -n "$imp" ]] || continue
        src="$(jq -r .src <<< "$imp")"
        dest="$(jq -r .dest <<< "$imp")"
        run_msb copy "$src" "sb-main:$ctx_guest_dir/imports/$dest" >&2
      done < <(jq -c '.imports[]' <<< "$plan_json")
      run_msb exec sb-main -- chmod -R 777 "$ctx_guest_dir/imports"
    fi

    # 进入 launcher（sec-run 凭据注入由 run_msb 统一处理）；
    # launcher 发布 meta 后目录所有权归 launcher，宿主回收 trap 解除
    trap - EXIT INT TERM HUP
    run_code=0

    run_msb exec sb-main "${terminal[@]}" -- bash "$LAUNCHER" "$ctx_id" "$plan_json" "$current_cwd" "$@" || run_code=$?

    exit "$run_code"
    ;;

  shell)
    exec "$0" run -t bash "$@"
    ;;

  -h|--help|help)
    usage 0
    ;;

  *)
    usage 1
    ;;
esac
