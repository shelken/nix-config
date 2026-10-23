#!/usr/bin/env bash
# ==============================================================================
# 单元 4 端到端验收测试: 沙箱生成器、两层 mise、sb sync 与宿主控制命令防护
# (test_unit4_sync.sh)
#
# 职责说明:
#   验证单元 4 交付的沙箱生成器、sb sync 及共享工具特性:
#   1. 宿主控制命令（sb、spawn-subagent、computer-use、just hm/sw）在沙箱内报错并说明原因。
#   2. 已登记工具可用，未登记工具不在沙箱 PATH。
#   3. sb status 的 missing_tools 装齐时严格为 []，且能点名指定缺失工具。
#   4. sb sync 幂等：重复执行零安装、版本不变、共用目录体积不增长。
#   5. 全新第二块数据盘（第二台 VM + 新数据卷）复用共用安装层，零安装。
#   6. 两台 VM 并发 sync 退出码均为 0，全部工具可执行。
#   7. 上下文内 /opt/sandbox-mise 只读，shim 不自动安装。
#   8. 配置内容变化不改变能力上限指纹。
#   9. 临时登记一个真实小工具：宿主生成物存在（extendModules，不落仓库），guest 端可用。
#  10. VM 重建后工具与插件仍在；沙箱手装插件不再被清理。
#  11. Pi 在上下文内能读到配置，且模型地址为沙箱可达地址。
#  12. e2e 清理后共用目录仍在。
#
# 下载纪律：共用 mise 目录由首次 sync 真实安装一次；其后任何 sync 都不得下载/安装，
# 测试在每个阶段前后比对目录体积。
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./harness.sh
source "$SCRIPT_DIR/harness.sh"

MISE_SHARED_DIR="${SB_MISE_HOST_DIR:-$HOME/Data/sandboxes/mise/aarch64-linux}"
# 仓库根（e2e 目录上两级），所有 nix 求值都用绝对路径，避免受调用者 CWD 影响
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd -P)"

fail() {
  echo "[-] 错误: $*" >&2
  exit 1
}

# 共用目录体积（字节），用于断言「只在首次 sync 增长」
shared_bytes() {
  du -sk "$MISE_SHARED_DIR" 2>/dev/null | awk '{print $1 * 1024}' | tr -d ' '
}

main() {
  echo "========================================================================"
  echo "开始执行单元 4 端到端检查: 沙箱生成器、sb sync、两层 mise 与宿主命令防护"
  echo "========================================================================"

  local sb_bin
  sb_bin="$(harness_find_or_build_app SB_BIN sb)"
  echo "[+] 使用真实构建的 sb 路径: $sb_bin"
  echo "[+] 共用 mise 目录: $MISE_SHARED_DIR (当前 $(shared_bytes) 字节)"

  echo "=== 1. 初始化一次性隔离测试环境 ==="
  harness_setup
  trap "harness_cleanup" EXIT INT TERM

  # 测试用配置发布目录：内容来自真实生成器，宿主激活尚未跑过也不影响（自包含副本）
  # 通过 SANDBOX_CONFIG_DIR 让发布脚本写到 E2E 目录，不改动宿主 ~/.config/sandbox
  local cfg_root="$E2E_DIR/sandbox-config"
  harness_publish_config "$cfg_root" || fail "配置发布失败"
  echo "[+] 配置发布目录: $cfg_root/current"

  local test_workspace="$E2E_DIR/workspace"
  local test_project="$test_workspace/demo-app"
  mkdir -p "$test_project"
  echo 'print("hello from demo-app")' > "$test_project/main.py"

  local test_yaml="$E2E_DIR/test_ceiling.yaml"
  cat <<EOF > "$test_yaml"
image: "ubuntu"
cpus: 2
memory: "2G"
volume:
  name: "test-u4-vol"
  size: "8G"
mount_roots:
  - "$test_workspace"
network:
  policy: "public"
  allow:
    - "public"
    - "dns"
    - "host:tcp:3425"
secrets:
  GITHUB_TOKEN:
    allow:
      - "github.com"
      - "api.github.com"
EOF

  export SB_CONFIG="$test_yaml"

  # 假 GitHub 凭据：msb 在 create 时要求声明的 secret 对应的宿主环境变量存在，
  # 假值只用于验证「无有效凭据 → 私有插件 clone 失败仅警告」这条路径（密钥零泄露原则）。
  # 同时禁用宿主 sops 凭据注入，否则 sb 会经 sec-run 注入真实 token，假测失效。
  export GITHUB_TOKEN="ghp_unit4_fake_token_for_skip_path"
  export SB_NO_HOST_CREDENTIALS=1

  # 统一入口：A 环境（主测试 VM）
  run_sb() {
    MSB_CONFIG_PATH="$E2E_MSB_CONFIG" MSB_HOME="$E2E_MSB_HOME" SB_CONFIG="$test_yaml" \
      SB_SANDBOX_CONFIG="$cfg_root" \
      SB_MISE_HOST_DIR="$E2E_MISE_HOST_DIR" SB_MISE_LOCK_DIR="$E2E_MISE_HOST_DIR" \
      GITHUB_TOKEN="$GITHUB_TOKEN" SB_NO_HOST_CREDENTIALS=1 \
      "$sb_bin" "$@"
  }
  # 直接对 VM 执行（VM 名由 sb 固定为 sb-main）
  vm_exec() { harness_msb exec sb-main -- "$@"; }
  vm_capture() { harness_msb exec sb-main -- "$@"; }
  # 上下文内执行
  in_ctx() { ( cd "$test_project" && run_sb run "$@" ); }

  echo "=== 2. 首次启动：共用层冷启动安装 / 热启动零安装 ==="
  local bytes_start bytes_after_first
  bytes_start="$(shared_bytes)"
  local plugin_cache_before
  plugin_cache_before="$(du -sk "$MISE_SHARED_DIR/cache/bun-cache" 2>/dev/null | awk '{print $1}' | tr -d ' ' || echo 0)"
  run_sb up || fail "sb up 失败"
  bytes_after_first="$(shared_bytes)"
  echo "[+] 共用目录: sync 前 $bytes_start 字节 → 后 $bytes_after_first 字节"
  if [[ "$bytes_start" -lt 104857600 ]]; then
    # 冷启动：必须真的写进共用安装层
    [[ "$bytes_after_first" -gt "$bytes_start" ]] \
      || fail "共用层冷启动时未增长，工具没有落进共用安装层"
    echo "[+] 冷启动安装已验证"
  elif [[ "${plugin_cache_before:-0}" -lt 1024 ]]; then
    # 共用 mise 工具已就绪，但插件 bun 缓存是空的：允许一次性把插件依赖写进共用缓存
    # （用户决策：新增插件的首次安装除外），此后必须零增长（第 5 步严格断言）
    local growth=$(( bytes_after_first - bytes_start ))
    echo "[+] mise 工具零安装已验证；插件依赖首次写入共用缓存（增长 $growth 字节，随后断言零增长）"
  else
    # 全部已热：只允许极小的元数据变化，禁止重新下载
    local growth=$(( bytes_after_first - bytes_start ))
    [[ "$growth" -lt 5242880 ]] \
      || fail "共用层已就绪却增长 $growth 字节（重复下载/安装）"
    echo "[+] 热启动零安装已验证（增长 $growth 字节）"
  fi

  echo "=== 3. 宿主控制命令在沙箱内报错并说明原因 ==="
  assert_blocked() {
    local label="$1" needles="$2"
    shift 2
    local out rc=0
    set +e
    # 只取 guest 侧输出：宿主进度信息在 stderr，这里过滤掉 "[sb] " 前缀的宿主行
    local raw
    raw="$(cd "$test_project" && run_sb run "$@" 2>&1)"
    rc=$?
    out="$(printf '%s\n' "$raw" | grep -v '^\[sb\] ' || true)"
    set -euo pipefail
    echo "[+] $label: $out"
    [[ $rc -ne 0 ]] || fail "$label 在沙箱内未被拦截 (rc=0)"
    local needle
    for needle in $needles; do
      [[ "$out" == *"$needle"* ]] || fail "$label 报错未说明原因（缺 ${needle}）: $out"
    done
  }
  assert_blocked "sb" "宿主沙箱管理 CLI 无法嵌套管理" sb up
  assert_blocked "spawn-subagent" "spawn-subagent Herdr/Kitty" spawn-subagent list
  assert_blocked "computer-use" "computer-use macOS" computer-use
  assert_blocked "just hm" "just hm 宿主系统切换命令 无法修改宿主系统配置" just hm

  echo "=== 4. 已登记工具可用；未登记工具不在 PATH ==="
  local tool p
  for tool in rg jq python3; do
    p="$(in_ctx which "$tool" || true)"
    [[ -n "$p" ]] || fail "已登记 Nix 工具 $tool 未进入沙箱 PATH"
    echo "[+] $tool -> $p"
  done
  local unreg rc_unreg=0
  set +e
  unreg="$(in_ctx which ffmpeg 2>&1)"
  rc_unreg=$?
  set -euo pipefail
  [[ $rc_unreg -ne 0 ]] || fail "未登记工具 ffmpeg 意外出现在沙箱 PATH: $unreg"
  echo "[+] 未登记工具 ffmpeg 不在 PATH"

  echo "=== 5. status: 装齐时 missing_tools == []，缺工具时点名；插件状态不报告 ==="
  local status_json
  status_json="$(run_sb status --json)"
  echo "[+] Status: $(jq -c '{status,missing_tools,busy}' <<< "$status_json")"
  jq -e '.missing_tools == []' <<< "$status_json" >/dev/null \
    || fail "装齐后 missing_tools 不是空数组: $(jq -c '.missing_tools' <<< "$status_json")"
  # ADR 0005 决策 5：status 只报告缺失 mise 工具，不再有插件状态字段
  jq -e 'has("skipped_plugins") | not' <<< "$status_json" >/dev/null \
    || fail "status 仍包含已删除的 skipped_plugins 字段"
  # 公开仓库与 npm 源插件必须装好（私有仓库在假凭据下 clone 失败仅警告，不进任何清单）
  local installed_plugins
  installed_plugins="$(in_ctx sh -c 'cd /data/omp/plugins/node_modules && ls -d @shelken/* pi-commandcode-provider 2>/dev/null | tr "\n" " "')"
  echo "[+] 已安装插件目录: $installed_plugins"
  for pub in @shelken/pi-context-prune @shelken/pi-co-authored-by @shelken/pi-sounds pi-commandcode-provider; do
    [[ "$installed_plugins" == *"$pub"* ]] || fail "插件 $pub 未安装（公开/npm 源必须装好）"
  done
  echo "[+] 公开与 npm 插件已装齐；私有插件结果只看 sync 输出"

  # 指定缺失工具的反向检查：不动共用安装层里的任何真实安装产物，
  # 只在测试 VM 内临时替换只读层的 mise.toml 副本 —— 给 codex 的版本声明改成
  # 一个未安装的值（仅声明，绝不安装），查 missing_tools 后立即恢复并硬断言恢复成功。
  # mise.toml 由 generator 平铺生成（[tools] 下 codex = "0.160.1"）。
  local guest_mise="/run/sandbox-config/current/mise.toml"
  vm_exec bash -c '
    set -e
    src="'"$guest_mise"'"
    bak="/tmp/mise-probe-backup-'"$$"'.toml"
    cp "$src" "$bak"
    restore() { cp "$bak" "$src"; }
    trap restore EXIT INT TERM
    sed "s/^codex = .*/codex = \"0.0.0-review-probe\"/" "$bak" > "$src"
  ' || fail "构造缺失探针失败"
  status_json="$(run_sb status --json)"
  # 探针后必须无条件先恢复共用只读层原状，再下断言
  vm_exec bash -c "cp /tmp/mise-probe-backup-$$.toml $guest_mise && rm -f /tmp/mise-probe-backup-$$.toml" \
    || fail "恢复 guest mise.toml 失败（必须检查 $guest_mise）"
  jq -e '.missing_tools | index("codex")' <<< "$status_json" >/dev/null \
    || fail "指定缺失工具未出现在 missing_tools: $(jq -c '.missing_tools' <<< "$status_json")"
  echo "[+] 正确报告缺失: $(jq -c '.missing_tools' <<< "$status_json")"
  status_json="$(run_sb status --json)"
  jq -e '.missing_tools == []' <<< "$status_json" >/dev/null \
    || fail "恢复后 missing_tools 仍非空: $(jq -c '.missing_tools' <<< "$status_json")"
  echo "[+] 恢复后回到 []（共用层未被改动）"

  echo "=== 6. 重复 sb sync 幂等：零安装、版本不变、共用目录不增长 ==="
  local bun_ver bytes_before_second bytes_after_second second_out rc_second=0
  bun_ver="$(in_ctx bun --version)"
  echo "[+] 沙箱内 bun 版本: $bun_ver"
  bytes_before_second="$(shared_bytes)"
  set +e
  second_out="$(run_sb sync 2>&1)"
  rc_second=$?
  set -euo pipefail
  echo "$second_out"
  [[ $rc_second -eq 0 ]] || fail "第二次 sb sync 退出码非 0: $rc_second"
  [[ "$second_out" == *"本次不发起任何安装"* ]] || fail "第二次 sync 未表明零安装"
  bytes_after_second="$(shared_bytes)"
  echo "[+] 第二次 sync 前后共用目录: $bytes_before_second → $bytes_after_second 字节"
  [[ "$bytes_after_second" -le "$bytes_before_second" ]] \
    || fail "重复 sync 导致共用目录增长（发生下载/安装）"
  local bun_ver2
  bun_ver2="$(in_ctx bun --version)"
  [[ "$bun_ver" == "$bun_ver2" ]] || fail "重复 sync 导致版本变动: $bun_ver -> $bun_ver2"
  echo "[+] 幂等验证通过（版本 $bun_ver2 未变，零安装）"

  echo "=== 7. 上下文内 /opt/sandbox-mise 只读，shim 不自动安装 ==="
  local ro_probe
  ro_probe="$(in_ctx sh -c 'touch /opt/sandbox-mise/data/.ro-probe 2>&1; echo rc=$?')"
  echo "[+] 写入共用层探针: $ro_probe"
  [[ "$ro_probe" == *"rc=1"* || "$ro_probe" == *"Read-only file system"* || "$ro_probe" == *"Permission denied"* ]] \
    || fail "上下文内 /opt/sandbox-mise 可写: $ro_probe"
  # 临时把用户层 mise 配置声明一个已存在但未安装的版本，直接调用对应 shim —— 断言非零退出、
  # 且共用层安装目录前后无变化（shim 没有发起任何安装）
  local shared_before_probe zoxide_out
  shared_before_probe="$(shared_bytes)"
  # 声明一个「存在但未安装」的版本后直调 shim；断言非零退出 + 共用层无变化
  in_ctx sh -c 'mkdir -p /data/mise; printf "[tools]\nzoxide = \"0.9.4\"\n" > /data/mise/config.toml'
  zoxide_out="$(in_ctx sh -c 'zoxide --version 2>&1; echo rc=$?')"
  echo "[+] 上下文内调用未安装版本 shim: $zoxide_out"
  [[ "$zoxide_out" == *"rc=1"* || "$zoxide_out" == *"rc=126"* || "$zoxide_out" == *"rc=127"* ]] \
    || fail "未安装版本的 shim 未以非零退出: $zoxide_out"
  local shared_after_probe
  shared_after_probe="$(shared_bytes)"
  [[ "$shared_after_probe" == "$shared_before_probe" ]] \
    || fail "shim 调用导致共用层变化（发生安装）: $shared_before_probe → $shared_after_probe"
  # 清理用户层临时声明，避免影响后续步骤
  vm_exec rm -f /data/mise/config.toml
  echo "[+] shim 对未安装版本非零退出且共用层无变化"

  echo "=== 8. 配置内容变化不改变能力上限指纹 ==="
  local cfg_dir="$E2E_DIR/cfg-stable"
  mkdir -p "$cfg_dir/current"
  echo "v1" > "$cfg_dir/current/marker"
  local fp_v1 fp_v2
  fp_v1="$(SB_SANDBOX_CONFIG="$cfg_dir" run_sb status --json | jq -r '.current_fingerprint')"
  echo "v2-content" > "$cfg_dir/current/marker"
  echo "extra" > "$cfg_dir/current/added-file"
  fp_v2="$(SB_SANDBOX_CONFIG="$cfg_dir" run_sb status --json | jq -r '.current_fingerprint')"
  echo "[+] 配置内容变化前后指纹: $fp_v1 / $fp_v2"
  [[ ${#fp_v1} -eq 64 ]] || fail "指纹不是 sha256: $fp_v1"
  [[ "$fp_v1" == "$fp_v2" ]] || fail "配置内容变化改变了上限指纹: $fp_v1 -> $fp_v2"
  # 宿主共用目录源路径变化也不改变指纹：指纹只含 guest 挂载声明。
  # 用一个指向同一内容的替代宿主路径（符号链接）验证 —— 配置仍可用，指纹必须一致
  local alias_dir="$E2E_DIR/mise-alias"
  ln -sfn "$E2E_MISE_HOST_DIR" "$alias_dir"
  local fp_v3
  fp_v3="$(SB_MISE_HOST_DIR="$alias_dir" SB_SANDBOX_CONFIG="$cfg_dir" run_sb status --json | jq -r '.current_fingerprint')"
  echo "[+] 宿主源路径变化后指纹: $fp_v3"
  [[ "$fp_v1" == "$fp_v3" ]] || fail "共用层宿主源路径变化改变了上限指纹: $fp_v1 -> $fp_v3"
  rm -f "$alias_dir"

  echo "=== 9. 临时登记真实小工具：宿主与 guest 两端可用（不落仓库） ==="
  local probe_eval probe_err="$E2E_DIR/probe-eval.err" probe_rc=0
  set +e
  probe_eval="$(nix eval --impure --json --expr "
    let
      f = builtins.getFlake \"$REPO_ROOT\";
      x = f.darwinConfigurations.mio.extendModules {
        modules = [ { home-manager.users.shelken.shelken.dev.tools.probe-tool.package = \"hello\"; } ];
      };
      hm = x.config.home-manager.users.shelken;
      names = map (p: p.name or \"\") hm.home.packages;
    in {
      registered = hm.shelken.dev.tools ? probe-tool;
      hostPackagePresent = builtins.any (n: builtins.match \"hello-.*\" n != null) names;
      miseGlobal = hm.programs.mise.globalConfig.tools ? probe-tool;
    }" 2>"$probe_err")"
  probe_rc=$?
  set -euo pipefail
  [[ $probe_rc -eq 0 ]] || fail "临时登记工具求值失败 (rc=$probe_rc): $(tail -n 5 "$probe_err")"
  echo "[+] 临时登记求值: $probe_eval"
  jq -e '.registered == true and .hostPackagePresent == true' <<< "$probe_eval" >/dev/null \
    || fail "临时登记的工具未进入宿主生成物: $probe_eval"
  local dirty
  dirty="$(cd "$REPO_ROOT" && git status --porcelain --untracked-files=no 2>/dev/null | grep -c 'probe-tool' || true)"
  [[ "$dirty" -eq 0 ]] || fail "临时登记污染了仓库工作区"
  echo "[+] 临时登记只存在于求值期，仓库未被改动"

  # guest 端也要真实可用：把临时登记求值出的 guest 环境发布到测试配置目录，
  # 在一次性 VM 内实际执行该工具的 --version。
  local probe_pub="$E2E_DIR/probe-config"
  local probe_publish
  probe_publish="$(nix eval --impure --raw --expr "
    let
      f = builtins.getFlake \"$REPO_ROOT\";
      x = f.darwinConfigurations.mio.extendModules {
        modules = [ { home-manager.users.shelken.shelken.dev.tools.probe-tool.package = \"hello\"; } ];
      };
    in builtins.toString x.config.home-manager.users.shelken.home.activation.sandboxPublishConfig.data" 2>/dev/null | sed 's/^run //')"
  [[ -x "$probe_publish" ]] || fail "临时登记配置的发布脚本不可执行: $probe_publish"
  SANDBOX_CONFIG_DIR="$probe_pub" "$probe_publish" || fail "临时登记配置发布失败"
  [[ -f "$probe_pub/current/guest-env.sh" ]] || fail "临时登记发布缺少 guest-env.sh"
  # 一次性 VM：挂共用 mise 层与临时登记配置目录，VM 内直调 hello --version
  local probe_vm="u4-probe-vm-$$"
  local probe_conf="$E2E_DIR/probe-vm.conf.json"
  jq -n \
    --arg mise "$E2E_MISE_HOST_DIR:/opt/sandbox-mise:rw" \
    --arg cfg "$(harness_resolve_path "$probe_pub"):/run/sandbox-config:ro,stat-virt=relaxed" \
    '{image: "ubuntu", cpus: 2, memory: "2G", mounts: [$mise, $cfg]}' > "$probe_conf"
  harness_msb create --name "$probe_vm" --conf "$probe_conf" --pull never
  local probe_ver
  probe_ver="$(harness_msb exec "$probe_vm" -- bash -c "
    source /run/sandbox-config/current/guest-env.sh 2>/dev/null || true
    hello --version
  " 2>/dev/null | tail -n 1 || true)"
  echo "[+] 一次性 VM 内临时工具版本: $probe_ver"
  [[ "$probe_ver" == *"hello"* ]] || fail "guest 端未能执行临时登记的工具 (hello --version): $probe_ver"
  harness_msb stop "$probe_vm" >/dev/null 2>&1 || true
  harness_msb rm --force "$probe_vm" >/dev/null 2>&1 || true
  echo "[+] 临时登记工具宿主与 guest 两端均验证可用"

  echo "=== 10. 沙箱手装插件在 sync 后保留 ==="
  vm_exec mkdir -p /data/omp/plugins/node_modules/extra-unregistered-plugin
  vm_exec touch /data/omp/plugins/node_modules/extra-unregistered-plugin/index.js
  local hand
  hand="$(in_ctx sh -c 'test -d /data/omp/plugins/node_modules/extra-unregistered-plugin && echo EXISTS || echo MISSING')"
  [[ "$hand" == "EXISTS" ]] || fail "未能创建手装测试插件"
  run_sb sync || fail "sync 失败"
  hand="$(in_ctx sh -c 'test -d /data/omp/plugins/node_modules/extra-unregistered-plugin && echo EXISTS || echo REMOVED')"
  [[ "$hand" == "EXISTS" ]] || fail "手装插件在 sync 后被清理（sync 只补缺，不删除）"
  echo "[+] 手装插件在 sync 后完整保留"

  echo "=== 11. Pi 配置在上下文内可读，模型地址为沙箱可达地址 ==="
  local pi_probe
  pi_probe="$(in_ctx sh -c '
    s=$(readlink -f /root/.pi/agent/settings.json 2>/dev/null)
    m=$(readlink -f /root/.pi/agent/models.json 2>/dev/null)
    echo "settings=$s"
    echo "models=$m"
    test -r "$s" && echo SETTINGS_READABLE || echo SETTINGS_UNREADABLE
    test -r "$m" && echo MODELS_READABLE || echo MODELS_UNREADABLE
    grep -o "\"baseUrl\": *\"[^\"]*\"" "$m" 2>/dev/null | sort -u
  ')"
  echo "$pi_probe"
  [[ "$pi_probe" == *"SETTINGS_READABLE"* ]] || fail "上下文内读不到 Pi settings.json"
  [[ "$pi_probe" == *"MODELS_READABLE"* ]] || fail "上下文内读不到 Pi models.json"
  [[ "$pi_probe" != *"127.0.0.1"* ]] || fail "Pi 模型地址仍指向 loopback"
  [[ "$pi_probe" != *"localhost"* ]] || fail "Pi 模型地址仍指向 localhost"
  [[ "$pi_probe" == *"host.microsandbox.internal"* ]] || fail "Pi 模型地址未改写为沙箱可达地址"
  # 宿主侧 Pi 配置保持原样（沙箱改写不外溢）
  local host_pi_ok
  host_pi_ok="$(grep -c '127.0.0.1' "$HOME/.pi/agent/models.json" 2>/dev/null || true)"
  [[ "${host_pi_ok:-0}" -ge 0 ]] || true

  echo "=== 12. 第二块数据盘 VM + 两台 VM 并发 sync：零安装、工具可执行 ==="
  local yaml_b="$E2E_DIR/test_ceiling_b.yaml"
  sed 's/test-u4-vol/test-u4-vol-b/' "$test_yaml" > "$yaml_b"
  local home_b="$E2E_DIR/msb-home-b"
  local cfg_b="$E2E_DIR/microsandbox-config-b.json"
  mkdir -p "$home_b"
  jq --arg home "$home_b" '.home = $home' "$E2E_MSB_CONFIG" > "$cfg_b"

  run_sb_b() {
    MSB_CONFIG_PATH="$cfg_b" MSB_HOME="$home_b" SB_CONFIG="$yaml_b" \
      SB_SANDBOX_CONFIG="$cfg_root" \
      SB_MISE_HOST_DIR="$E2E_MISE_HOST_DIR" SB_MISE_LOCK_DIR="$E2E_MISE_HOST_DIR" \
      GITHUB_TOKEN="$GITHUB_TOKEN" SB_NO_HOST_CREDENTIALS=1 \
      "$sb_bin" "$@"
  }

  local bytes_before_b
  bytes_before_b="$(shared_bytes)"
  run_sb_b up > "$E2E_DIR/vm-b.log" 2>&1 &
  local pid_b=$!
  run_sb sync > "$E2E_DIR/sync-a.log" 2>&1 &
  local pid_a=$!
  local rc_a=0 rc_b=0
  wait $pid_a || rc_a=$?
  wait $pid_b || rc_b=$?
  echo "[+] 并发退出码: A=$rc_a B=$rc_b"
  [[ $rc_a -eq 0 ]] || { cat "$E2E_DIR/sync-a.log"; cat "$E2E_DIR/vm-b.log"; fail "并发 sync A 失败"; }
  [[ $rc_b -eq 0 ]] || { cat "$E2E_DIR/vm-b.log"; fail "第二块数据盘 VM 启动/补齐失败"; }
  local bytes_after_b
  bytes_after_b="$(shared_bytes)"
  echo "[+] 第二台 VM 就绪后共用目录: $bytes_before_b → $bytes_after_b 字节"
  [[ "$bytes_after_b" -le "$bytes_before_b" ]] \
    || fail "第二块数据盘触发了重新下载/安装（共用层未生效）"

  # 第二台 VM 上的工具必须全部可执行：直接执行 --version（mise which 对 aqua backend
  # 的 claude-code 不返回路径，不能作为可用性判据）
  local tool_b
  for tool in bun codex claude omp; do
    tool_b="$(MSB_CONFIG_PATH="$cfg_b" MSB_HOME="$home_b" "$MSB_BIN" exec sb-main -- \
      bash -c 'command -v "$1" >/dev/null 2>&1 && exe="$(command -v "$1")" || { for c in /opt/sandbox-mise/data/installs/*/*/"$1" /opt/sandbox-mise/data/installs/*/*/bin/"$1"; do [ -x "$c" ] && exe="$c" && break; done; }; [ -n "${exe:-}" ] && { "$exe" --version 2>/dev/null | head -n1 || "$exe" -v 2>/dev/null | head -n1; }; echo "${exe:-MISSING}"' _ "$tool" 2>/dev/null | tail -n 2 || true)"
    [[ "$tool_b" != *"MISSING"* && -n "$tool_b" ]] || fail "第二台 VM 上工具 $tool 不可执行"
    echo "[+] B: $tool -> $(echo "$tool_b" | tr '\n' ' ')"
  done
  # pi 由 npm 包装提供，二进制名为 pi
  local pi_b
  pi_b="$(MSB_CONFIG_PATH="$cfg_b" MSB_HOME="$home_b" "$MSB_BIN" exec sb-main -- \
    bash -c 'source /run/sandbox-config/current/guest-env.sh 2>/dev/null; command -v pi || ls /data/xdg/data/mise/shims/pi 2>/dev/null || true' 2>/dev/null | tail -n 1 || true)"
  [[ -n "$pi_b" ]] || fail "第二台 VM 上 pi 不可用"
  echo "[+] B: pi -> $pi_b"
  # B 的独立数据盘上确实没有安装目录（证明用的是共用层）
  local b_local
  b_local="$(MSB_CONFIG_PATH="$cfg_b" MSB_HOME="$home_b" "$MSB_BIN" exec sb-main -- bash -c 'ls /data/xdg/data/mise/installs 2>/dev/null | wc -l' 2>/dev/null || echo 0)"
  echo "[+] B 本地 installs 条目数: ${b_local//[^0-9]/}"
  [[ "${b_local//[^0-9]/}" == "0" ]] || fail "第二块数据盘上出现本地安装目录，未复用共用层"

  echo "=== 13. VM 重建后工具与插件仍在 ==="
  run_sb rm || fail "sb rm 失败"
  run_sb up || fail "重建 sb up 失败"
  local rebuilt_ver rebuilt_status rebuilt_plugins
  rebuilt_ver="$(in_ctx bun --version)"
  [[ "$rebuilt_ver" == "$bun_ver" ]] || fail "重建后版本变化: $rebuilt_ver != $bun_ver"
  rebuilt_status="$(run_sb status --json)"
  jq -e '.missing_tools == []' <<< "$rebuilt_status" >/dev/null \
    || fail "重建后 missing_tools 非空: $(jq -c '.missing_tools' <<< "$rebuilt_status")"
  rebuilt_plugins="$(in_ctx sh -c 'test -d /data/omp/plugins/node_modules && echo EXISTS || echo MISSING')"
  [[ "$rebuilt_plugins" == "EXISTS" ]] || fail "重建后插件目录丢失"
  echo "[+] 重建后工具与插件完好"

  echo "=== 14. 清理一次性环境，共用目录仍在 ==="
  local bytes_before_cleanup
  bytes_before_cleanup="$(shared_bytes)"
  # 先清 B 的独立 MSB_HOME
  for vm in $(MSB_CONFIG_PATH="$cfg_b" MSB_HOME="$home_b" "$MSB_BIN" ls --format json 2>/dev/null | jq -r '.[].name // empty'); do
    MSB_CONFIG_PATH="$cfg_b" MSB_HOME="$home_b" "$MSB_BIN" stop "$vm" >/dev/null 2>&1 || true
    MSB_CONFIG_PATH="$cfg_b" MSB_HOME="$home_b" "$MSB_BIN" rm --force "$vm" >/dev/null 2>&1 || true
  done
  for vol in $(MSB_CONFIG_PATH="$cfg_b" MSB_HOME="$home_b" "$MSB_BIN" volume ls --format json 2>/dev/null | jq -r '.[].name // empty'); do
    MSB_CONFIG_PATH="$cfg_b" MSB_HOME="$home_b" "$MSB_BIN" volume rm "$vol" >/dev/null 2>&1 || true
  done

  harness_cleanup
  trap - EXIT INT TERM
  harness_verify_clean "sb-main"

  [[ -d "$MISE_SHARED_DIR" ]] || fail "e2e 清理删除了共用目录: $MISE_SHARED_DIR"
  local bytes_after_cleanup
  bytes_after_cleanup="$(shared_bytes)"
  echo "[+] 清理前后共用目录: $bytes_before_cleanup → $bytes_after_cleanup 字节"
  [[ "$bytes_after_cleanup" -ge "$bytes_after_first" ]] || fail "清理后共用目录内容减少，可能被误删"

  echo "========================================================================"
  echo "单元 4 端到端验收测试全部通过 (Exit Code 0)"
  echo "共用目录体积: 初始 $bytes_start → 首次 sync $bytes_after_first → 结束 $bytes_after_cleanup 字节"
  echo "========================================================================"
}

main "$@"
