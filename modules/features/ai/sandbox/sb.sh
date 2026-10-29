#!/usr/bin/env bash
# sb: Agent 沙箱宿主管理 CLI
# 职责：
# 1. 管理主 VM (sb-main) 生命周期与跨进程互斥锁
# 2. 读取原生 sb.yaml 上限配置，按需自动创建、启动或重建 VM
# 3. 解析并校验项目 .sandbox.yaml 授权，比对批准哈希
# 4. 复制 imports 导入文件，调度 guest 执行上下文隔离器 (sb-launcher)
# 5. 串行化执行沙箱内工具与插件补齐 (sb sync)
set -euo pipefail

# 默认参数（由 Nix 运行时或外部环境注入）
DEFAULT_MSB_CONFIG="${DEFAULT_MSB_CONFIG:-}"
DEFAULT_MSB_HOME="${DEFAULT_MSB_HOME:-}"
DEFAULT_YAML="${DEFAULT_YAML:-}"
LAUNCHER="${LAUNCHER:-}"
GUEST_STATUS="${GUEST_STATUS:-}"

export MSB_CONFIG_PATH="${MSB_CONFIG_PATH:-$DEFAULT_MSB_CONFIG}"
export MSB_HOME="${MSB_HOME:-$DEFAULT_MSB_HOME}"
export SB_MISE_HOST_DIR="${SB_MISE_HOST_DIR:-$HOME/Data/sandboxes/mise/aarch64-linux}"
SB_APPROVAL_DIR="$MSB_HOME/approvals"
SB_LOCK_DIR="$MSB_HOME/locks"
mkdir -p "$SB_LOCK_DIR"

# -----------------------------------------------------------------------------
# 1. 跨进程生命周期锁 (Life-cycle Lock)
# -----------------------------------------------------------------------------
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
  exec 8>&-
}

require_sb_lock() {
  local action="$1"
  acquire_sb_lock 300 && return 0
  echo "[-] 错误: 主 VM sb-main 生命周期锁被其他进程长期持有，放弃本次${action}" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# 2. Microsandbox (msb) 驱动与凭据注入
# -----------------------------------------------------------------------------
find_msb() {
  if command -v msb >/dev/null 2>&1; then
    echo "msb"
  else
    echo "[-] 错误: PATH 中没有 msb（用 mise 安装 microsandbox，并确认 mise 已激活）" >&2
    exit 1
  fi
}

MSB="$(find_msb)"

if command -v sec-run >/dev/null 2>&1 && [[ "${SB_NO_HOST_CREDENTIALS:-0}" != "1" ]]; then
  SEC_RUN=(sec-run)
else
  SEC_RUN=()
fi

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

vm_status() {
  "$MSB" inspect "$1" --format json 2>/dev/null | jq -r '.status // empty' 2>/dev/null || true
}

wait_for_vm_running() {
  local vm_name="$1" max_attempts=30 attempt=0
  while [[ $attempt -lt $max_attempts ]]; do
    local st
    st="$(vm_status "$vm_name")"
    [[ "$st" == "Running" ]] && return 0
    sleep 0.5
    attempt=$((attempt + 1))
  done
  echo "[-] 错误: 等待 VM $vm_name 达到 Running 状态超时" >&2
  return 1
}

# -----------------------------------------------------------------------------
# 3. 项目策略解析与授权检查 (Plan & Trust)
# -----------------------------------------------------------------------------
expand_path() {
  local p="$1" home="$HOME"
  # shellcheck disable=SC2016
  local brace_home='${HOME}'
  p="${p/#\~/$home}"
  p="${p//$brace_home/$home}"
  printf '%s\n' "$p"
}

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
  local plan_json="$1" yaml_file="$2" state default_grants_json
  state="$(approval_state "$(jq -r '.project_root' <<< "$plan_json")")"
  default_grants_json="$(yq -o=json '.network.default_grant // []' "$yaml_file")"
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

resolve_and_validate_plan() {
  local cwd="$1" ceiling_yaml="$2"
  local ceiling_json
  ceiling_json="$(yq -o=json '.' "$ceiling_yaml")"

  local -a allowed_roots=()
  while IFS= read -r root_path; do
    [[ -n "$root_path" ]] || continue
    local expanded
    expanded="$(expand_path "$root_path")"
    [[ -d "$expanded" ]] && allowed_roots+=("$(realpath "$expanded")")
  done < <(jq -r '(.mount_roots // [])[]' <<< "$ceiling_json")

  local project_root=""
  if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    project_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  [[ -z "$project_root" ]] && project_root="$cwd"
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

  local git_common_dir=""
  if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local cd_raw
    cd_raw="$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null || true)"
    [[ -n "$cd_raw" ]] && git_common_dir="$(cd "$cwd" && realpath "$cd_raw")"
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
      echo "[-] 错误: worktree 的 git common dir $git_common_dir 超出沙箱能力上限，请先把该路径加入 mount_roots" >&2
      return 1
    fi
  fi

  local proj_cfg="$project_root/.sandbox.yaml"
  local imports_json="[]" network_json="[]" paths_json="[]"

  if [[ -f "$proj_cfg" ]]; then
    local cfg_json
    cfg_json="$(yq -o=json '.' "$proj_cfg")"

    local -a verified_imports=()
    local target_form='^(~/|/)[^/]'
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      local src target rel
      src="$(jq -r '.src? // empty' <<< "$item")"
      target="$(jq -r '.target? // empty' <<< "$item")"
      if [[ -z "$src" || -z "$target" ]]; then
        echo "[-] 错误: .sandbox.yaml 的 imports 每项都要写 src 与 target: $item" >&2
        return 1
      fi
      rel="${target#\~/}"
      rel="${rel#/}"
      if [[ ! "$target" =~ $target_form || "$target" == */ || "/$target/" == */../* || "$rel" != */* ]]; then
        echo "[-] 错误: imports 的 target 必须以 ~/ 或 / 开头、不含 ..、位于某个子目录内: $target" >&2
        return 1
      fi
      src="$(expand_path "$src")"
      [[ "$src" != /* ]] && src="$project_root/$src"
      if [[ ! -f "$src" ]]; then
        echo "[-] 错误: .sandbox.yaml 中声明的导入文件不存在: $src" >&2
        return 1
      fi
      verified_imports+=("$(jq -n --arg src "$(realpath "$src")" --arg target "$target" '{src: $src, target: $target, dir: ($target | sub("/[^/]*$"; ""))}')")
    done < <(jq -c '.imports[]? // empty' <<< "$cfg_json")

    if [[ ${#verified_imports[@]} -gt 0 ]]; then
      imports_json="$(printf '%s\n' "${verified_imports[@]}" | jq -s '
        (map(.target) | group_by(.) | map(select(length > 1)) | first) as $dup
        | if $dup then error("imports 的 target 重复: \($dup[0])") else . end
        | (map(.dir) | unique) as $dirs
        | map(. as $i | $i + {stage: ($dirs | index($i.dir))})')"
    fi

    local -a verified_network=()
    while IFS= read -r net_target; do
      [[ -n "$net_target" ]] || continue
      if [[ ! "$net_target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?$ ]]; then
        echo "[-] 错误: .sandbox.yaml 的 network 只接受 IP 或 IP:端口: $net_target" >&2
        return 1
      fi
      verified_network+=("$net_target")
    done < <(jq -r '.network[]? // empty' <<< "$cfg_json")
    [[ ${#verified_network[@]} -gt 0 ]] && network_json="$(printf '%s\n' "${verified_network[@]}" | jq -R . | jq -s .)"

    local -a verified_paths=()
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      local p ro="false"
      if jq -e 'type == "string"' <<< "$item" >/dev/null 2>&1; then
        local raw_p
        raw_p="$(jq -r . <<< "$item")"
        if [[ "$raw_p" == *:ro ]]; then p="${raw_p%:ro}"; ro="true"; else p="$raw_p"; fi
      else
        p="$(jq -r '.path // empty' <<< "$item")"
        jq -e '.readonly == true or .ro == true' <<< "$item" >/dev/null 2>&1 && ro="true"
      fi
      p="${p/#\~/$HOME}"
      [[ "$p" != /* ]] && p="$project_root/$p"
      if [[ ! -e "$p" ]]; then
        echo "[-] 错误: .sandbox.yaml 中声明的额外路径不存在: $p" >&2
        return 1
      fi
      local real_p
      real_p="$(realpath "$p")"
      local p_allowed=0
      for ar in "${allowed_roots[@]}"; do
        if [[ "$real_p" == "$ar" || "$real_p" == "$ar"/* ]]; then p_allowed=1; break; fi
      done
      if [[ "$p_allowed" -eq 0 ]]; then
        echo "[-] 错误: .sandbox.yaml 中额外路径 $real_p 超出能力上限 (未落在 mount_roots 内)" >&2
        return 1
      fi
      verified_paths+=("$(jq -n --arg path "$real_p" --argjson ro "$ro" '{path: $path, readonly: $ro}')")
    done < <(jq -c '.paths[]? // empty' <<< "$cfg_json")
    [[ ${#verified_paths[@]} -gt 0 ]] && paths_json="$(printf '%s\n' "${verified_paths[@]}" | jq -s .)"
  fi

  local -a default_grants=()
  while IFS= read -r grant; do
    [[ -n "$grant" ]] || continue
    if [[ ! "$grant" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):[0-9]+$ ]]; then
      echo "[-] 错误: sb.yaml network.default_grant 只接受 IP:端口: $grant" >&2
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
    '{project_root: $pr, git_common_dir: $gcd, cwd: $cwd, imports: $imp, network: $net, paths: $paths, default_allow: $def_allow}'
}

# -----------------------------------------------------------------------------
# 4. VM 配置生成与上限指纹 (VM Generation & Fingerprint)
# -----------------------------------------------------------------------------
generate_msb_config() {
  local src_yaml="$1" dst_json="$2"
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
    [[ ! -e "$expanded" ]] && mkdir -p "$expanded"
    roots+=("$(realpath "$expanded")")
  done < <(jq -r '(.mount_roots // [])[]' <<< "$raw_json")

  local roots_json="[]"
  [[ ${#roots[@]} -gt 0 ]] && roots_json="$(printf '%s\n' "${roots[@]}" | jq -R . | jq -s .)"

  local real_sandbox_cfg=""
  if [[ -n "${SB_SANDBOX_CONFIG:-}" && -d "${SB_SANDBOX_CONFIG:-}" ]]; then
    real_sandbox_cfg="$(realpath "$SB_SANDBOX_CONFIG")"
  elif [[ -d "$HOME/.config/sandbox/current" ]]; then
    real_sandbox_cfg="$(realpath "$HOME/.config/sandbox")"
  fi

  local sb_mount_json="[]"
  if [[ -n "$real_sandbox_cfg" && -d "$real_sandbox_cfg" ]]; then
    sb_mount_json="$(printf '%s\n' "$real_sandbox_cfg:/run/sandbox-config:ro,stat-virt=relaxed" | jq -R . | jq -s .)"
  fi

  mkdir -p "$SB_MISE_HOST_DIR"
  local mise_real
  mise_real="$(realpath "$SB_MISE_HOST_DIR")"
  local sb_mise_json
  sb_mise_json="$(printf '%s\n' "$mise_real:/opt/sandbox-mise:rw" | jq -R . | jq -s .)"
  SB_MISE_HOST_DIR_REAL="$mise_real"

  local network_json secrets_json
  network_json="$(jq -c '(.network // {"policy": "public", "allow": ["public", "dns"]}) | del(.default_grant)' <<< "$raw_json")"
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
    '([{"named": $vol, "target": "/data"}, $nix] + $sb_mounts + $sb_mise + ($roots | map("\(.):\(.)"))) as $mounts |
     {image: $img, cpus: $cpus, memory: $mem, mounts: $mounts, network: $net} +
     (if ($sec | keys | length) > 0 then {secrets: $sec} else {} end)' > "$dst_json"
}

get_config_fingerprint() {
  local conf_file="$1"
  jq -S -c --arg mise_mount "${SB_MISE_HOST_DIR_REAL:-$SB_MISE_HOST_DIR}:/opt/sandbox-mise:rw" '
    .mounts |= map(if . == $mise_mount then "__SB_MISE_HOST__:/opt/sandbox-mise:rw" else . end)
  ' "$conf_file" | sha256sum | cut -d' ' -f1
}

# -----------------------------------------------------------------------------
# 5. 上下文状态探测与工具补齐 (Context Status & Sync)
# -----------------------------------------------------------------------------
query_active_contexts() {
  local vm_name="$1"
  BUSY_COUNT="" BUSY_ERROR=""
  if [[ "$(vm_status "$vm_name")" != "Running" ]]; then
    BUSY_COUNT=0
    return 0
  fi
  local err_file out rc=0
  err_file="$(mktemp)"
  out="$("$MSB" exec "$vm_name" -- bash "$LAUNCHER" --check-busy 2>"$err_file")" || rc=$?
  local err
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

query_guest_tool_state() {
  local vm_name="$1" out rc=0
  out="$("$MSB" exec "$vm_name" -- bash "$GUEST_STATUS" 2>/dev/null)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "[-] 错误: 查询 $vm_name 缺失工具失败 (rc=$rc)" >&2
    return 1
  fi
  [[ -z "$out" ]] && { printf '%s\n' '{"missing":[]}'; return 0; }
  printf '%s\n' "$out" | jq -R -s -c '
    split("\n") | map(select(length > 0) | split("\t")) as $rows
    | {missing: [$rows[] | select(.[0] == "missing") | .[1]]}'
}

exec_sync_guest() {
  local vm_name="$1"
  shift
  run_msb exec "$vm_name" --stream --no-stdin -- bash -c '
    if [[ -f /run/sandbox-config/current/sync-guest.sh ]]; then
      exec bash /run/sandbox-config/current/sync-guest.sh "$@"
    else
      echo "[!] 警告: 未在沙箱内找到 sync-guest.sh，跳过自动补齐" >&2
      exit 1
    fi
  ' argv0 "$@"
}

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

# -----------------------------------------------------------------------------
# 6. VM 就绪状态机 (VM Ensure & Lifecycle)
# -----------------------------------------------------------------------------
ensure_vm_locked() {
  local vm_name="sb-main" yaml_file="$YAML_FILE"
  local tmp_cfg
  tmp_cfg="$(mktemp "/tmp/sb-${vm_name}-XXXXXX.json")"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_cfg'" EXIT INT TERM

  generate_msb_config "$yaml_file" "$tmp_cfg"
  local current_fp
  current_fp="$(get_config_fingerprint "$tmp_cfg")"

  local ceiling_json vol_name vol_size
  ceiling_json="$(yq -o=json '.' "$yaml_file")"
  vol_name="$(jq -r '.volume.name // "sb-main-data"' <<< "$ceiling_json")"
  vol_size="$(jq -r '.volume.size // "8G"' <<< "$ceiling_json")"

  if ! "$MSB" volume inspect "$vol_name" >/dev/null 2>&1; then
    echo "[sb] 数据卷 $vol_name 不存在，正在创建 (ext4 disk, 大小: $vol_size)..." >&2
    "$MSB" volume create "$vol_name" --kind disk --size "$vol_size" >&2
  fi

  local -a create_args=(--name "$vm_name" --conf "$tmp_cfg" --label "ceiling_fingerprint=$current_fp")
  local vm_state
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
      if ! query_active_contexts "$vm_name"; then
        echo "[-] 错误: 无法确认主 VM $vm_name 是否有上下文在运行，本次不重建。原因: $BUSY_ERROR" >&2
        exit 1
      fi
      if [[ "$BUSY_COUNT" -gt 0 ]]; then
        echo "[-] 错误: 能力上限已变，主 VM 有 $BUSY_COUNT 个上下文在运行，全部退出后再启动即按新上限重建。" >&2
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
    echo "[sb] 首次创建自动执行 sb sync 补齐工具..." >&2
    run_sync_with_mise_lock "$vm_name" >&2 || echo "[sb] 首次工具自动补齐未全部完成 (可稍后通过 sb sync 补齐)" >&2
  fi

  rm -f "$tmp_cfg"
  trap - EXIT INT TERM
}

# -----------------------------------------------------------------------------
# 7. CLI 命令路由与分发
# -----------------------------------------------------------------------------
usage() {
  cat <<'EOF'
用法:
sb up                创建或启动主 VM (sb-main)，已运行且上限一致则复用，上限变化且空闲则重建
sb down              停止主 VM
sb rm [--force]       删除主 VM，保留数据卷；有运行中上下文时拒绝，--force 强制删除
sb sync              补齐沙箱内的 mise 工具与 OMP 插件 (幂等，只装缺失项；宿主写锁串行化)
sb status            查看主 VM 状态、规格、能力上限指纹一致性与缺失工具
sb plan [--json]     显示当前项目解析后的授权：挂载、导入、放行的私网目标与批准状态
sb trust             批准当前项目的 .sandbox.yaml (内容哈希变了要重新批准)
sb run [-t] CMD…     在当前项目执行上下文内运行命令 (TTY 自适应)
sb shell             进入当前项目执行上下文的交互式 Bash shell
EOF
  exit "${1:-0}"
}

YAML_FILE="${SB_CONFIG:-}"
if [[ -z "$YAML_FILE" ]]; then
  if [[ -f "$HOME/.config/sandbox/sb.yaml" ]]; then
    YAML_FILE="$HOME/.config/sandbox/sb.yaml"
  else
    YAML_FILE="$DEFAULT_YAML"
  fi
fi

cmd="${1:-}"
shift || true

case "$cmd" in
  up)
    require_sb_lock 启动/重建
    ensure_vm_locked
    release_sb_lock
    ;;

  down)
    require_sb_lock 停止
    echo "[sb] 正在停止主 VM sb-main..." >&2
    "$MSB" stop sb-main "$@"
    release_sb_lock
    ;;

  rm)
    force=0
    declare -a rm_args=()
    for arg in "$@"; do
      if [[ "$arg" == "--force" || "$arg" == "-f" ]]; then force=1; else rm_args+=("$arg"); fi
    done
    require_sb_lock 删除
    if [[ "$force" -eq 0 ]]; then
      if ! query_active_contexts sb-main; then
        echo "[-] 错误: 无法确认主 VM sb-main 是否有上下文在运行，拒绝删除。原因: $BUSY_ERROR" >&2
        exit 1
      fi
      if [[ "$BUSY_COUNT" -gt 0 ]]; then
        echo "[-] 错误: 主 VM sb-main 有 $BUSY_COUNT 个上下文在运行，拒绝删除。可用 sb rm --force 强制" >&2
        exit 1
      fi
    fi
    echo "[sb] 正在删除主 VM sb-main (保留数据卷)..." >&2
    "$MSB" rm --force sb-main "${rm_args[@]}"
    release_sb_lock
    ;;

  status)
    vm_name="sb-main"
    status="Not created" cpus="-" memory="-" vm_fp="-" current_fp="-" ceiling_match="not_created" busy="idle"
    if vm_state="$("$MSB" inspect "$vm_name" --format json 2>/dev/null)"; then
      status="$(jq -r '.status // empty' <<< "$vm_state")"
      cpus="$(jq -r '.active_config.resources.cpus // .config.resources.cpus // "-"' <<< "$vm_state")"
      mem_mib="$(jq -r '.active_config.resources.memory_mib // .config.resources.memory_mib // "-"' <<< "$vm_state")"
      if [[ "$mem_mib" =~ ^[0-9]+$ ]]; then
        if (( mem_mib % 1024 == 0 )); then memory="$((mem_mib / 1024))G"; else memory="${mem_mib}M"; fi
      else
        memory="$mem_mib"
      fi
      vm_fp="$(jq -r '.config.labels.ceiling_fingerprint // empty' <<< "$vm_state")"
      [[ -z "$vm_fp" ]] && vm_fp="-"
      if query_active_contexts "$vm_name"; then
        [[ "$BUSY_COUNT" -gt 0 ]] && busy="busy ($BUSY_COUNT)"
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

    missing_tools_str="无"
    if [[ "$status" == "Running" ]]; then
      guest_state="$(query_guest_tool_state "$vm_name")"
      if jq -e 'type == "object" and has("missing")' <<< "$guest_state" >/dev/null 2>&1; then
        missing_tools_json="$(jq -c '.missing' <<< "$guest_state")"
        [[ "$(jq 'length' <<< "$missing_tools_json")" -gt 0 ]] && missing_tools_str="$(jq -r 'join(", ")' <<< "$missing_tools_json")"
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
    plan_json="$(resolve_and_validate_plan "$(pwd -P)" "$YAML_FILE")"
    if [[ "${1:-}" == "--json" || "${1:-}" == "-j" ]]; then
      jq --arg a "$(approval_state "$(jq -r '.project_root' <<< "$plan_json")")" '. + {approval: $a}' <<< "$plan_json"
    else
      print_plan "$plan_json" "$YAML_FILE"
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
    print_plan "$plan_json" "$YAML_FILE"
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
      terminal=(--stream --no-stdin)
    fi

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t) terminal=(-t); shift ;;
        --) shift; break ;;
        *) break ;;
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

    imports_count="$(jq -r '.imports | length' <<< "$plan_json")"
    ctx_guest_dir="/run/sandbox/contexts/$ctx_id"
    if [[ "$imports_count" -gt 0 ]]; then
      stage_dirs=()
      while IFS= read -r stage; do
        stage_dirs+=("$ctx_guest_dir/imports/$stage")
      done < <(jq -r '[.imports[].stage] | unique[]' <<< "$plan_json")
      # shellcheck disable=SC2016
      run_msb exec sb-main -- bash -c 'mkdir -p "${@:2}" && touch "$1"' _ "$ctx_guest_dir/starting" "${stage_dirs[@]}"
      # shellcheck disable=SC2329
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
      run_msb exec sb-main -- chmod -R u+rwX,go-rwx "$ctx_guest_dir/imports"
    fi

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
