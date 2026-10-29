#!/usr/bin/env bash
# 由 Nix 用 writeShellApplication 打包（构建期过 shellcheck）；Nix 只替换下面的大写占位符
# （配置路径、发布目录、launcher 与 guest 查询脚本路径），业务逻辑全部在本文件。
set -euo pipefail

DEFAULT_MSB_CONFIG="${DEFAULT_MSB_CONFIG:-}"
DEFAULT_MSB_HOME="${DEFAULT_MSB_HOME:-}"
DEFAULT_YAML="${DEFAULT_YAML:-}"
LAUNCHER="${LAUNCHER:-}"
GUEST_STATUS="${GUEST_STATUS:-}"

export MSB_CONFIG_PATH="${MSB_CONFIG_PATH:-$DEFAULT_MSB_CONFIG}"
export MSB_HOME="${MSB_HOME:-$DEFAULT_MSB_HOME}"
# 宿主共用 mise 目录真实路径；默认值与 default.nix 注入的一致，
# 新开终端前环境变量尚未生效时也指向同一目录；e2e 覆盖它把一次性 VM 挂到 harness 共用目录
export SB_MISE_HOST_DIR="${SB_MISE_HOST_DIR:-$HOME/Data/sandboxes/mise/aarch64-linux}"

# 主 VM 生命周期锁：跨进程互斥，锁目录固定在 $MSB_HOME/locks，
# 不放在可被删除的 VM 目录 ($MSB_HOME/sandboxes/<vm>) 内。
# 只包住「检查上限指纹 → 必要时重建 → 启动 VM」，原因见 README「设计决策」。
SB_LOCK_DIR="$MSB_HOME/locks"
mkdir -p "$SB_LOCK_DIR"

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

# 获取生命周期锁，失败即报错退出。action 是「放弃本次<动作>」里的动作词。
require_sb_lock() {
  local action="$1"
  acquire_sb_lock 300 && return 0
  echo "[-] 错误: 主 VM sb-main 生命周期锁被其他进程长期持有，放弃本次${action}" >&2
  exit 1
}

YAML_FILE="${SB_CONFIG:-}"
if [[ -z "$YAML_FILE" ]]; then
  if [[ -f "$HOME/.config/sandbox/sb.yaml" ]]; then
    YAML_FILE="$HOME/.config/sandbox/sb.yaml"
  else
    YAML_FILE="$DEFAULT_YAML"
  fi
fi

find_msb() {
  if command -v msb >/dev/null 2>&1; then
    echo "msb"
  else
    echo "[-] 错误: PATH 中没有 msb（用 mise 安装 microsandbox，并确认 mise 已激活）" >&2
    exit 1
  fi
}

MSB="$(find_msb)"

# sec-run 包装判定：sb 在宿主侧启动 msb 时自动注入凭据（GITHUB_TOKEN 等）。
# e2e 用假凭据验证 secret 替换，必须能关闭注入，否则宿主真实凭据会让假测失效；
# SB_NO_HOST_CREDENTIALS=1 显式禁用。
if command -v sec-run >/dev/null 2>&1 && [[ "${SB_NO_HOST_CREDENTIALS:-0}" != "1" ]]; then
  SEC_RUN=(sec-run)
else
  SEC_RUN=()
fi

# 只有 create / start 需要宿主环境里的真实凭据：msb 的 --secret 在 VM 启动时读取宿主环境变量，
# 之后的占位符替换由运行中的 VM 完成，exec / copy 等不再需要。
# 每次 sec-run 都是一次 op run（解析引用、可能触发 1Password 授权弹窗），所以只在这两处包
run_msb() {
  case "${1:-}" in
    create | start)
      if [[ ${#SEC_RUN[@]} -gt 0 ]]; then
        "${SEC_RUN[@]}" "$MSB" "$@"
        return
      fi
      ;;
  esac
  "$MSB" "$@"
}

usage() {
  cat <<'EOF'
用法:
sb up                创建或启动主 VM (sb-main)，已运行且上限一致则复用，上限变化且空闲则重建
sb down              停止主 VM
sb rm [--force]       删除主 VM，保留数据卷；有运行中上下文时拒绝，--force 强制删除
sb sync              补齐沙箱内的 mise 工具与 OMP 插件 (幂等，只装缺失项；宿主写锁串行化)
sb status            查看主 VM 状态、规格、能力上限指纹一致性与缺失工具
sb plan [--json]     显示当前项目解析后的授权：挂载、导入、放行的私网目标与批准状态 (不创建 VM，被拒绝时先看它)
sb trust             批准当前项目的 .sandbox.yaml (内容哈希变了要重新批准；未批准时 sb run 直接报错)
sb run [-t] CMD…     在当前项目执行上下文内运行命令 (TTY 自适应)
sb shell             进入当前项目执行上下文的交互式 Bash shell
EOF
  exit "${1:-0}"
}

# 展开路径里的 ~、${HOME} 前缀/引用（不引入 eval；realpath 与相对根解析由调用点负责）
expand_path() {
  local p="$1" home="$HOME"
  # shellcheck disable=SC2016  # 刻意保持字面量，交给下面的参数展开匹配
  local brace_home='${HOME}'
  p="${p/#\~/$home}"
  p="${p//$brace_home/$home}"
  printf '%s\n' "$p"
}

# .sandbox.yaml 的批准记录按规范化内容的哈希保存，不看项目路径：同一份文件在所有 worktree 里只批准一次。
# 记录放在 $MSB_HOME 下（宿主状态）；沙箱里的 sb 被宿主命令桩拒绝，Agent 批准不了自己
SB_APPROVAL_DIR="$MSB_HOME/approvals"

# 键排序、去注释后的哈希：只改格式或注释不使批准失效
sandbox_cfg_hash() {
  yq -o=json -I=0 'sort_keys(..)' "$1" | sha256sum | cut -d' ' -f1
}

approval_state() {
  local cfg="$1/.sandbox.yaml"
  if [[ ! -f "$cfg" ]]; then
    echo none
  elif [[ -f "$SB_APPROVAL_DIR/$(sandbox_cfg_hash "$cfg")" ]]; then
    echo approved
  else
    echo unapproved
  fi
}

print_plan() {
  local plan_json="$1" state default_grants_json
  state="$(approval_state "$(jq -r '.project_root' <<< "$plan_json")")"
  default_grants_json="$(yq -o=json '.network.default_grant // []' "$YAML_FILE")"
  jq -r --argjson dg "$default_grants_json" --arg state "$state" '
    def section(t; a): t, (if (a | length) == 0 then "  无" else (a[] | "  " + .) end);
    .project_root as $pr
    | (.git_common_dir // "") as $gcd
    | "项目根: \($pr)",
      (if $gcd != "" and $gcd != $pr and ($gcd | startswith($pr + "/") | not) then "git common dir: \($gcd)" else empty end),
      section("额外路径:"; .paths | map(.path + (if .readonly then "（只读）" else "" end))),
      section("导入文件:"; .imports | map(.src + " → " + .target)),
      section("放行的私网目标:"; .network | map(. as $t | $t + (if ($dg | index($t)) != null then "（sb.yaml 默认放行）" else "（项目声明）" end))),
      section("放行的宿主端口:"; .default_allow),
      "批准状态: \({approved: "已批准", unapproved: "未批准，确认以上内容后执行 sb trust", none: "无 .sandbox.yaml，不需要批准"}[$state])"
  ' <<< "$plan_json"
}

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
  image="$(jq -r '.image // "ubuntu"' <<< "$raw_json")"
  cpus="$(jq -r '.cpus // 4' <<< "$raw_json")"
  memory="$(jq -r '.memory // "8G"' <<< "$raw_json")"
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

  # 配置发布源优先级：显式覆盖 > 宿主持久发布目录
  # 持久目录在更新 current 链接时保持路径不变，内容变化（模型、提示词、工具清单）
  # 因此不会改变上限指纹。
  local real_sandbox_cfg=""
  if [[ -n "${SB_SANDBOX_CONFIG:-}" && -d "${SB_SANDBOX_CONFIG:-}" ]]; then
    real_sandbox_cfg="$(realpath "$SB_SANDBOX_CONFIG")"
  elif [[ -d "$HOME/.config/sandbox/current" ]]; then
    real_sandbox_cfg="$(realpath "$HOME/.config/sandbox")"
  fi

  local -a sb_mount_entries=()
  if [[ -n "$real_sandbox_cfg" && -d "$real_sandbox_cfg" ]]; then
    sb_mount_entries+=("$real_sandbox_cfg:/run/sandbox-config:ro,stat-virt=relaxed")
  fi
  local sb_mount_json
  if [[ ${#sb_mount_entries[@]} -gt 0 ]]; then
    sb_mount_json="$(printf '%s\n' "${sb_mount_entries[@]}" | jq -R . | jq -s .)"
  else
    sb_mount_json="[]"
  fi

  # 宿主共用 mise 目录：挂进主 VM，guest 路径固定 /opt/sandbox-mise。
  # 上限指纹只含 guest 路径与读写属性，不含宿主真实路径。
  # 宿主真实路径取 SB_MISE_HOST_DIR；首次使用时目录还不存在，直接创建
  mkdir -p "$SB_MISE_HOST_DIR"
  local mise_real
  mise_real="$(realpath "$SB_MISE_HOST_DIR")"
  local sb_mise_json
  sb_mise_json="$(printf '%s\n' "$mise_real:/opt/sandbox-mise:rw" | jq -R . | jq -s .)"
  # 供 get_config_fingerprint 在计算指纹时识别并规范化该挂载条目
  SB_MISE_HOST_DIR_REAL="$mise_real"

  # default_grant 是上下文级授权，不进 VM 配置，也就不影响上限指纹
  local network_json
  network_json="$(jq -c '(.network // {"policy": "public", "allow": ["public", "dns"]}) | del(.default_grant)' <<< "$raw_json")"

  local secrets_json
  secrets_json="$(jq -c '.secrets // {}' <<< "$raw_json")"

  jq -n \
    --arg img "$image" \
    --argjson cpus "$cpus" \
    --arg mem "$memory" \
    --arg vol "$vol_name" \
    --arg nix "/nix/store:/nix/store:ro,stat-virt=relaxed" \
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
    {
      image: $img,
      cpus: $cpus,
      memory: $mem,
      mounts: $mounts,
      network: $net
    }
    + (if ($sec | keys | length) > 0 then {secrets: $sec} else {} end)
    ' > "$dst_json"
}

# 计算上限指纹：先在副本里把共用 mise 挂载的宿主源路径规范化为固定占位值，
# 再对 canonical JSON 做哈希 —— 实际 VM 配置仍使用真实路径。
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
    st="$(vm_status "$vm_name")"
    if [[ "$st" == "Running" ]]; then
      return 0
    fi
    sleep 0.5
    attempt=$((attempt + 1))
  done
  echo "[-] 错误: 等待 VM $vm_name 达到 Running 状态超时" >&2
  return 1
}

# 查询 VM 当前状态（Running / Stopped / 空）。查询失败返回空串，调用方按非 Running 处理。
vm_status() {
  "$MSB" inspect "$1" --format json 2>/dev/null | jq -r '.status // empty' 2>/dev/null || true
}

# 取主 VM 内活跃执行上下文数，写入全局 BUSY_COUNT；取不到时返回 1，原因写入 BUSY_ERROR。
# 调用方据此区分「确认空闲 0」「确认忙 N」「查不到」三种状态，不要把查不到当成忙。
query_active_contexts() {
  local vm_name="$1"
  local st out err err_file rc=0
  BUSY_COUNT=""
  BUSY_ERROR=""
  st="$(vm_status "$vm_name")"
  if [[ "$st" != "Running" ]]; then
    BUSY_COUNT=0
    return 0
  fi
  err_file="$(mktemp)"
  out="$("$MSB" exec "$vm_name" -- bash "$LAUNCHER" --check-busy 2>"$err_file")" || rc=$?
  err="$(head -c 400 "$err_file" 2>/dev/null || true)"
  rm -f "$err_file"
  err="${err//$'\n'/ }"
  if [[ $rc -ne 0 ]]; then
    BUSY_ERROR="guest 查询退出码 $rc${err:+，stderr: $err}"
    return 1
  fi
  out="${out//[[:space:]]/}"
  if [[ ! "$out" =~ ^[0-9]+$ ]]; then
    BUSY_ERROR="guest 返回非数字输出 [${out}]${err:+，stderr: $err}"
    return 1
  fi
  BUSY_COUNT="$out"
}

# 判定主 VM 是否有运行中的执行上下文：唯一来源是 guest 内 launcher 的登记表。
# 计数取不到时按忙处理（宁可拒绝重建，也不打断可能正在运行的上下文）。
is_vm_busy() {
  query_active_contexts "$1" || return 0
  [[ "$BUSY_COUNT" -gt 0 ]]
}

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
  if [[ -z "$out" ]]; then
    printf '%s\n' '{"missing":[]}'
    return 0
  fi
  printf '%s\n' "$out" | jq -R -s -c '
    split("\n") | map(select(length > 0) | split("\t")) as $rows
    | {missing: [$rows[] | select(.[0] == "missing") | .[1]]}'
}

exec_sync_guest() {
  local vm_name="$1"
  shift
  # sync 不读 stdin。msb 的 --stream 在 stdin 是终端时报错，--no-stdin 让它在终端与管道下都能跑
  run_msb exec "$vm_name" --stream --no-stdin -- bash -c '
    if [[ -f /run/sandbox-config/current/sync-guest.sh ]]; then
      exec bash /run/sandbox-config/current/sync-guest.sh "$@"
    else
      echo "[!] 警告: 未在沙箱内找到 sync-guest.sh，跳过自动补齐" >&2
      exit 1
    fi
  ' argv0 "$@"
}

# 获取共用 mise 写锁后执行 sync（调用前必须已持有主 VM 生命周期锁）。
# 锁目录固定在共用 mise 层根目录，跨 VM 串行化所有对安装层的写入。
run_sync_with_mise_lock() {
  local vm_name="$1"
  shift
  local lock_dir="${SB_MISE_LOCK_DIR:-$SB_MISE_HOST_DIR}"
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
    require_sb_lock 启动
    ensure_vm_locked
    release_sb_lock
  elif [[ "$(vm_status "$vm_name")" != "Running" ]]; then
    echo "[sb] VM $vm_name 处于停止状态，正在启动..." >&2
    require_sb_lock 启动
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

  # 确保数据卷存在（删除 VM 时保留，重新挂载即持久数据）
  if ! "$MSB" volume inspect "$vol_name" >/dev/null 2>&1; then
    echo "[sb] 数据卷 $vol_name 不存在，正在创建 (ext4 disk, 大小: $vol_size)..." >&2
    "$MSB" volume create "$vol_name" --kind disk --size "$vol_size" >&2
  fi

  local -a create_args=(--name "$vm_name" --conf "$tmp_cfg" --label "ceiling_fingerprint=$current_fp")

  if vm_state="$("$MSB" inspect "$vm_name" --format json 2>/dev/null)"; then
    local vm_status vm_fp
    vm_status="$(jq -r '.status // empty' <<< "$vm_state")"
    vm_fp="$(jq -r '.config.labels.ceiling_fingerprint // empty' <<< "$vm_state")"

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
      # 上限发生变化；锁内重读忙碌状态：
      # 空闲 → 直接重建；忙 → 只报错并给出运行中上下文数，不登记任何状态
      if ! query_active_contexts "$vm_name"; then
        echo "[-] 错误: 无法确认主 VM $vm_name 内是否有执行上下文在运行，本次不重建以免打断它们。原因: $BUSY_ERROR" >&2
        exit 1
      fi
      if [[ "$BUSY_COUNT" -gt 0 ]]; then
        echo "[-] 错误: 能力上限已变（$yaml_file 生成的上限指纹与主 VM 不一致），主 VM 有 $BUSY_COUNT 个执行上下文在运行，全部退出后再启动即按新上限重建。" >&2
        exit 1
      fi
      echo "[sb] 检测到能力上限变化且主 VM $vm_name 空闲，正在重建 (保留数据盘 $vol_name)..." >&2
      "$MSB" stop "$vm_name" >/dev/null 2>&1 || true
      "$MSB" rm --force "$vm_name" >/dev/null 2>&1 || true
      run_msb create "${create_args[@]}" >&2
      wait_for_vm_running "$vm_name"
      echo "[sb] 主 VM $vm_name 重建完成并已启动" >&2
    fi
  else
    echo "[sb] 正在创建主 VM: $vm_name (上限指纹: ${current_fp:0:12})..." >&2
    run_msb create "${create_args[@]}" >&2
    wait_for_vm_running "$vm_name"
    echo "[sb] 主 VM $vm_name 创建并启动成功" >&2
    # 首次创建自动补齐一次工具；已持有生命周期锁，只补共用 mise 写锁
    echo "[sb] 首次创建自动执行 sb sync 补齐工具..." >&2
    run_sync_with_mise_lock "$vm_name" >&2 || echo "[sb] 首次工具自动补齐未全部完成 (可稍后通过 sb sync 补齐)" >&2
  fi

  rm -f "$tmp_cfg"
  trap - EXIT INT TERM
}

sb_up() {
  require_sb_lock 启动/重建
  ensure_vm_locked
  release_sb_lock
}

resolve_and_validate_plan() {
  local cwd="$1"
  local ceiling_yaml="$2"

  local ceiling_json
  ceiling_json="$(yq -o=json '.' "$ceiling_yaml")"

  local -a allowed_roots=()
  while IFS= read -r root_path; do
    [[ -n "$root_path" ]] || continue
    local expanded
    expanded="$(expand_path "$root_path")"
    if [[ -d "$expanded" ]]; then
      allowed_roots+=("$(realpath "$expanded")")
    fi
  done < <(jq -r '(.mount_roots // [])[]' <<< "$ceiling_json")

  local project_root=""
  if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    project_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  if [[ -z "$project_root" ]]; then
    project_root="$cwd"
  fi
  project_root="$(realpath "$project_root")"

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

  # Worktree 自动加绑 git common dir；不在挂载根内时无法透传给 guest，
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

  local proj_cfg="$project_root/.sandbox.yaml"
  local imports_json="[]"
  local network_json="[]"
  local paths_json="[]"

  if [[ -f "$proj_cfg" ]]; then
    local cfg_json
    cfg_json="$(yq -o=json '.' "$proj_cfg")"

    # 校验 imports：target 是上下文内的路径；src 是任意宿主文件，是否放行由 sb trust 的批准决定

    local -a verified_imports=()
    local target_form='^(~/|/)[^/]'
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      local src target rel
      src="$(jq -r '.src? // empty' <<< "$item")"
      target="$(jq -r '.target? // empty' <<< "$item")"
      if [[ -z "$src" || -z "$target" ]]; then
        echo "[-] 错误: .sandbox.yaml 的 imports 每项都要写 src 与 target，收到: $item" >&2
        return 1
      fi
      # 目标目录会被暂存目录整体遮住，所以 target 不能直接位于 HOME 或 / 下
      rel="${target#\~/}"
      rel="${rel#/}"
      if [[ ! "$target" =~ $target_form || "$target" == */ || "/$target/" == */../* || "$rel" != */* ]]; then
        echo "[-] 错误: imports 的 target 必须以 ~/ 或 / 开头、不含 ..、位于某个子目录内（例如 ~/.kube/config），收到: $target" >&2
        return 1
      fi

      src="$(expand_path "$src")"
      if [[ "$src" != /* ]]; then
        src="$project_root/$src"
      fi
      if [[ ! -f "$src" ]]; then
        echo "[-] 错误: .sandbox.yaml 中声明的导入文件不存在: $src" >&2
        return 1
      fi
      local real_src
      real_src="$(realpath "$src")"

      verified_imports+=("$(jq -n --arg src "$real_src" --arg target "$target" '{src: $src, target: $target, dir: ($target | sub("/[^/]*$"; ""))}')")
    done < <(jq -c '.imports[]? // empty' <<< "$cfg_json")

    # stage：同一目标目录的导入共用一个暂存目录，launcher 以目录形式绑定到该目录
    if [[ ${#verified_imports[@]} -gt 0 ]]; then
      local imports_err
      if ! imports_json="$(printf '%s\n' "${verified_imports[@]}" | jq -s '
        (map(.target) | group_by(.) | map(select(length > 1)) | first) as $dup
        | if $dup then error("imports 的 target 重复: \($dup[0])") else . end
        | (map(.dir) | unique) as $dirs
        | map(. as $i | $i + {stage: ($dirs | index($i.dir))})' 2>&1)"; then
        imports_err="$imports_json"
        echo "[-] 错误: ${imports_err#*): }" >&2
        return 1
      fi
    fi

    # 校验 network 的写法；私网目标没有上限，是否放行由 sb trust 的批准决定
    local -a verified_network=()
    while IFS= read -r net_target; do
      [[ -n "$net_target" ]] || continue
      if [[ ! "$net_target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?$ ]]; then
        echo "[-] 错误: .sandbox.yaml 的 network 只接受 IP 或 IP:端口，收到: $net_target" >&2
        return 1
      fi
      verified_network+=("$net_target")
    done < <(jq -r '.network[]? // empty' <<< "$cfg_json")

    if [[ ${#verified_network[@]} -gt 0 ]]; then
      network_json="$(printf '%s\n' "${verified_network[@]}" | jq -R . | jq -s .)"
    fi

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

  # sb.yaml 声明的所有上下文默认放行的私网 IP:端口（如家里的模型服务），与项目声明的目标合并
  local -a default_grants=()
  while IFS= read -r grant; do
    [[ -n "$grant" ]] || continue
    if [[ ! "$grant" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):[0-9]+$ ]]; then
      echo "[-] 错误: sb.yaml network.default_grant 只接受 IP:端口，收到: $grant" >&2
      return 1
    fi
    default_grants+=("$grant")
  done < <(jq -r '.network.default_grant[]? // empty' <<< "$ceiling_json")
  if [[ ${#default_grants[@]} -gt 0 ]]; then
    network_json="$(printf '%s\n' "${default_grants[@]}" | jq -R . | jq -s --argjson proj "$network_json" '$proj + . | unique')"
  fi

  local default_allow_json
  default_allow_json="$(jq -c '[.network.allow[]? | select(. | test("^host:tcp:"))]' <<< "$ceiling_json")"

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
    require_sb_lock 停止
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
    require_sb_lock 删除
    # 有运行中的执行上下文时拒绝直接删除，--force 才强制（避免一键打断所有 Agent）
    if [[ "$force" -eq 0 ]]; then
      if ! query_active_contexts sb-main; then
        echo "[-] 错误: 无法确认主 VM sb-main 内是否有执行上下文在运行，拒绝删除。原因: $BUSY_ERROR。确认全部退出后重试，或用 sb rm --force 强制 (会打断所有上下文)" >&2
        exit 1
      fi
      if [[ "$BUSY_COUNT" -gt 0 ]]; then
        echo "[-] 错误: 主 VM sb-main 有 $BUSY_COUNT 个执行上下文正在运行，拒绝删除。全部退出后重试，或用 sb rm --force 强制 (会打断所有上下文)" >&2
        exit 1
      fi
    fi
    echo "[sb] 正在删除主 VM sb-main (保留数据卷)..." >&2
    "$MSB" rm --force sb-main "${rm_args[@]}"
    release_sb_lock
    ;;

  status)
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
      if [[ -z "$vm_fp" ]]; then
        vm_fp="-"
      fi
      if query_active_contexts "$vm_name"; then
        if [[ "$BUSY_COUNT" -gt 0 ]]; then
          busy="busy ($BUSY_COUNT)"
        fi
      else
        busy="unknown ($BUSY_ERROR)"
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
    ;;

  plan)
    # 只解析并校验当前项目的授权，不创建 VM，也不启动上下文
    plan_json="$(resolve_and_validate_plan "$(pwd -P)" "$YAML_FILE")"
    if [[ "${1:-}" == "--json" || "${1:-}" == "-j" ]]; then
      jq --arg a "$(approval_state "$(jq -r '.project_root' <<< "$plan_json")")" '. + {approval: $a}' <<< "$plan_json"
    else
      print_plan "$plan_json"
    fi
    ;;

  trust)
    plan_json="$(resolve_and_validate_plan "$(pwd -P)" "$YAML_FILE")"
    project_root="$(jq -r '.project_root' <<< "$plan_json")"
    if [[ ! -f "$project_root/.sandbox.yaml" ]]; then
      echo "[sb] $project_root 没有 .sandbox.yaml，不需要批准"
      exit 0
    fi
    cfg_hash="$(sandbox_cfg_hash "$project_root/.sandbox.yaml")"
    mkdir -p "$SB_APPROVAL_DIR"
    : > "$SB_APPROVAL_DIR/$cfg_hash"
    print_plan "$plan_json"
    echo "[+] 已批准 $project_root/.sandbox.yaml (${cfg_hash:0:12})"
    ;;

  sync)
    sb_sync "$@"
    ;;

  run)
    terminal=(--stream)
    if [[ -t 0 && -t 1 ]]; then
      terminal=(-t)
    elif [[ -t 0 ]]; then
      # stdin 是终端而 stdout 被重定向：msb 的 --stream 要求 stdin 为管道或 --no-stdin
      terminal=(--stream --no-stdin)
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
    if [[ "$(approval_state "$project_root")" == "unapproved" ]]; then
      echo "[-] 错误: $project_root/.sandbox.yaml 未批准，或批准后已变更。先执行 sb plan 查看授权内容，确认后执行 sb trust" >&2
      exit 1
    fi
    ctx_id="ctx_$(date +%s)_$RANDOM"

    require_sb_lock 启动
    ensure_vm_locked
    release_sb_lock

    # 复制导入文件（若声明）：先在 guest 登记「启动中」标记，宽限期内清扫与忙碌计数
    # 都视该目录为占用（凭据复制窗口不被并发启动误删）；复制失败或宿主中断时由
    # trap 回收整个上下文目录，凭据不在 guest 残留
    imports_count="$(jq -r '.imports | length' <<< "$plan_json")"
    ctx_guest_dir="/run/sandbox/contexts/$ctx_id"
    if [[ "$imports_count" -gt 0 ]]; then
      stage_dirs=()
      while IFS= read -r stage; do
        stage_dirs+=("$ctx_guest_dir/imports/$stage")
      done < <(jq -r '[.imports[].stage] | unique[]' <<< "$plan_json")
      # shellcheck disable=SC2016  # 单引号脚本交给 guest 的 bash 展开
      run_msb exec sb-main -- bash -c 'mkdir -p "${@:2}" && touch "$1"' _ "$ctx_guest_dir/starting" "${stage_dirs[@]}"
      # shellcheck disable=SC2329  # 仅经 trap 间接调用
      host_reclaim_ctx() {
        run_msb exec sb-main -- rm -rf "$ctx_guest_dir" 2>/dev/null || true
      }
      trap host_reclaim_ctx EXIT INT TERM HUP
      while IFS= read -r imp; do
        [[ -n "$imp" ]] || continue
        src="$(jq -r .src <<< "$imp")"
        target="$(jq -r .target <<< "$imp")"
        stage="$(jq -r .stage <<< "$imp")"
        run_msb copy "$src" "sb-main:$ctx_guest_dir/imports/$stage/${target##*/}" >&2
      done < <(jq -c '.imports[]' <<< "$plan_json")
      # 属主是 guest root，进入上下文后映射为上下文用户；其他用户不可读
      run_msb exec sb-main -- chmod -R u+rwX,go-rwx "$ctx_guest_dir/imports"
    fi

    # 进入 launcher（exec 不需要宿主凭据，凭据只在 VM create/start 时注入，见 run_msb）；
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
