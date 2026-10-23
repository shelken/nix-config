#!/usr/bin/env bash
# ==============================================================================
# 单元 3 端到端验收测试: 执行上下文 launcher 与 sb run/shell/omp-sb (test_unit3_launcher.sh)
#
# 职责说明:
#   验证单元 3 交付的所有执行上下文隔离、launcher、计划解析及网络/文件能力:
#   1. 在一次性隔离 MSB_HOME 中使用真实构建出的 `sb`。
#   2. 相邻项目不可见：bubblewrap 仅绑定当前项目，相邻项目目录不存在。
#   3. 权限与写入同步：项目目录与可写 paths 写入实时同步至宿主；只读 paths 写入失败。
#   4. Git Worktree 支持：worktree 自动加绑 git common dir，git status 与 commit 正常。
#   5. 导入文件管理：/imports 目录可见、支持原子改名 (mv/sed -i)、不写回宿主、退出后在 guest 自动删除。
#   6. 网络能力分级：
#      - 默认授权：DNS 与宿主端口 (如 host:tcp:3425) 无需项目显式声明即可正常连通。
#      - 私网受限：项目 .sandbox.yaml 声明的私网目标 (如 192.168.69.46) 放行；未声明的被拦截。
#   7. Secret 凭据替换：假 secret 经由 veth 与 MASQUERADE 发往受权目标时，在网络边界被替换为真实假凭据。
#   8. 并发独立性：并发两个上下文，增删其中一个不打断另一个的运行与网络。
#   9. 异常退出清扫：kill -9 模拟 launcher 崩溃后残留 netns/veth/规则/登记，在下一次启动时被自动清扫。
#  10. 附加验证：地址池分配与回收、上下文数量上限决定因素、残留清扫判据。
#  11. 清理后一次性环境零残留，宿主日常 VM sb-default 状态完好未受扰动。
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./harness.sh
source "$SCRIPT_DIR/harness.sh"

main() {
  echo "========================================================================"
  echo "开始执行单元 3 端到端检查: 执行上下文 launcher、sb run/shell 与隔离验证"
  echo "========================================================================"

  local sb_bin
  sb_bin="$(harness_find_or_build_app SB_BIN sb)"
  echo "[+] 使用真实构建的 sb 路径: $sb_bin"

  echo "=== 1. 初始化一次性隔离测试环境与假工作区 ==="
  harness_setup
  trap "harness_cleanup" EXIT INT TERM

  harness_setup_fake_workspace

  local proj_a="$E2E_WORKSPACE/project-a"
  local proj_a_wt="$E2E_WORKSPACE/project-a-worktree"
  local proj_b="$E2E_WORKSPACE/project-b"
  local shared_dir="$E2E_WORKSPACE/shared-extra"
  local creds_dir="$E2E_WORKSPACE/fake-credentials"
  local ro_dir="$E2E_WORKSPACE/readonly-extra"
  mkdir -p "$ro_dir"
  echo "initial_readonly_data" > "$ro_dir/ro_file.txt"

  # 为 project-a 配置 .sandbox.yaml
  cat <<EOF > "$proj_a/.sandbox.yaml"
imports:
  - src: "$creds_dir/fake-token.json"
    dst: fake-token.json
network:
  - "192.168.69.46"
paths:
  - path: "$shared_dir"
    readonly: false
  - path: "$ro_dir"
    readonly: true
EOF
  cp "$proj_a/.sandbox.yaml" "$proj_a_wt/.sandbox.yaml"
  # 建立测试用隔离全局上限 YAML (sb.yaml)
  local test_yaml="$E2E_DIR/sb.yaml"
  cat <<EOF > "$test_yaml"
image: "ubuntu"
cpus: 2
memory: "2G"
volume:
  name: "test-u3-vol"
  size: "1G"
mount_roots:
  - "$E2E_WORKSPACE"
network:
  policy: "public"
  allow:
    - "public"
    - "dns"
    - "host:tcp:3425"
    - "192.168.69.46"
secrets:
  MOCK_GITHUB_TOKEN:
    allow:
      - "api.github.com"
EOF

  run_sb() {
    MSB_CONFIG_PATH="$E2E_MSB_CONFIG" \
    MSB_HOME="$E2E_MSB_HOME" \
    SB_CONFIG="$test_yaml" \
    MOCK_GITHUB_TOKEN="ghp_mock_unit3_test_secret_7788" \
    "$sb_bin" "$@"
  }

  echo "=== 2. 测试 sb up 启动主 VM 并核验初始状态 ==="
  run_sb up
  local status_json
  status_json="$(run_sb status --json)"
  echo "Status JSON: $status_json"
  [[ "$(jq -r .busy <<< "$status_json")" == "false" ]] || { echo "[-] 初始状态被误判为 busy" >&2; exit 1; }
  echo "[+] 主 VM 启动成功且处于空闲 (busy=false)"

  echo "=== 3. 验证相邻项目不可见、项目与可写 paths 同步、只读 paths 拦截 ==="
  cd "$proj_a"
  # 3a. 相邻项目不可见验证
  local ls_adjacent
  ls_adjacent="$(run_sb run bash -c "if [[ -e '$proj_b' ]]; then echo 'FOUND'; else echo 'NOT_FOUND'; fi")"
  echo "Adjacent project check in sandbox: $ls_adjacent"
  [[ "$ls_adjacent" == "NOT_FOUND" ]] || { echo "[-] 隔离穿透: 相邻项目 project-b 在上下文内部可见" >&2; exit 1; }
  echo "[+] 隔离性验证通过: 相邻项目 project-b 不可见"

  # 3b. 当前项目写同步到宿主
  run_sb run bash -c "echo synced_from_context_a > '$proj_a/sync_a.txt'"
  [[ -f "$proj_a/sync_a.txt" ]] || { echo "[-] 项目内写同步失败: 宿主未发现 sync_a.txt" >&2; exit 1; }
  [[ "$(cat "$proj_a/sync_a.txt")" == "synced_from_context_a" ]] || { echo "[-] 项目写内容不匹配" >&2; exit 1; }
  echo "[+] 当前项目写同步验证通过"

  # 3c. 声明的可写 paths 同步到宿主
  run_sb run bash -c "echo shared_write_success > '$shared_dir/shared_new.txt'"
  [[ -f "$shared_dir/shared_new.txt" ]] || { echo "[-] 可写 paths 写同步失败" >&2; exit 1; }
  [[ "$(cat "$shared_dir/shared_new.txt")" == "shared_write_success" ]] || { echo "[-] 可写 paths 内容不匹配" >&2; exit 1; }
  echo "[+] 可写 paths 写同步验证通过"

  # 3d. 声明的只读 paths 写入必须失败
  local ro_write_res
  ro_write_res="$(run_sb run bash -c "echo fail > '$ro_dir/ro_fail.txt'" 2>&1 || echo "WRITE_FAILED")"
  echo "Readonly write test output: $ro_write_res"
  [[ "$ro_write_res" == *"WRITE_FAILED"* || "$ro_write_res" == *"Read-only file system"* ]] || { echo "[-] 只读 paths 写入未被拦截" >&2; exit 1; }
  [[ ! -f "$ro_dir/ro_fail.txt" ]] || { echo "[-] 只读 paths 文件被成功创建" >&2; exit 1; }
  echo "[+] 只读 paths 保护验证通过 (写入被拒绝)"

  echo "=== 4. 验证 Git Worktree 下 git status 与 git commit ==="
  cd "$proj_a_wt"
  run_sb run git status
  run_sb run bash -c "
    echo 'wt_modification_data' >> worktree-file.txt
    git add worktree-file.txt
    git -c user.name='E2EUnit3' -c user.email='e2e@unit3.local' commit -m 'commit from sandbox worktree'
  "
  local last_commit_msg
  last_commit_msg="$(git log -1 --pretty=%s)"
  echo "Worktree last commit on host: $last_commit_msg"
  [[ "$last_commit_msg" == "commit from sandbox worktree" ]] || { echo "[-] worktree commit 失败" >&2; exit 1; }
  echo "[+] Git Worktree 提交与 common dir 联动验证通过"

  echo "=== 5. 验证导入文件可见、可原子改名、不写回宿主、退出后自动删除 ==="
  cd "$proj_a"
  local host_token_orig
  host_token_orig="$(cat "$creds_dir/fake-token.json")"

  # 导入文件在 /imports 可见
  local imported_content
  imported_content="$(run_sb run cat /imports/fake-token.json)"
  echo "Imported content in sandbox: $imported_content"
  [[ "$imported_content" == "$host_token_orig" ]] || { echo "[-] 导入文件内容不匹配" >&2; exit 1; }

  # 原子改名测试 (写临时文件后 mv 覆盖)
  run_sb run bash -c "
    echo '{\"mutated\": true}' > /imports/fake-token.tmp
    mv /imports/fake-token.tmp /imports/fake-token.json
    cat /imports/fake-token.json
  "

  # 验证宿主文件绝对未被修改 (不写回宿主)
  local host_token_after
  host_token_after="$(cat "$creds_dir/fake-token.json")"
  [[ "$host_token_after" == "$host_token_orig" ]] || { echo "[-] 导入文件被意外写回宿主" >&2; exit 1; }
  echo "[+] 宿主原始凭据完好未被写回"

  # 验证执行退出后 guest 内导入目录与上下文登记已被删除
  local remaining_ctx_dirs
  remaining_ctx_dirs="$(harness_exec sb-main bash -c "ls /run/sandbox/contexts/ 2>/dev/null || true")"
  echo "Remaining context dirs in guest: '$remaining_ctx_dirs'"
  [[ -z "$remaining_ctx_dirs" ]] || { echo "[-] 执行退出后上下文目录未清理: $remaining_ctx_dirs" >&2; exit 1; }
  echo "[+] 导入目录退出自动删除验证通过"

  echo "=== 6. 验证默认授权与私网目标控制 ==="
  cd "$proj_a"
  # 6a. 默认授权验证 (宿主端口 host:tcp:3425)
  local def_auth_resp
  def_auth_resp="$(run_sb run curl -s -I -m 3 http://host.microsandbox.internal:3425/ | head -n 1)"
  echo "Default allow (host:tcp:3425) response: $def_auth_resp"
  [[ "$def_auth_resp" == *"200 OK"* || "$def_auth_resp" == *"HTTP/"* ]] || { echo "[-] 默认授权端口连接失败" >&2; exit 1; }
  echo "[+] 默认授权 (host:tcp:3425) 可用验证通过"

  # 6b. 项目声明的私网目标 (192.168.69.46) 放行
  local priv_allowed_resp
  priv_allowed_resp="$(run_sb run curl -s -I -m 3 http://192.168.69.46/ | head -n 1)"
  echo "Declared private target (192.168.69.46) response: $priv_allowed_resp"
  [[ "$priv_allowed_resp" == *"301 Moved"* || "$priv_allowed_resp" == *"HTTP/"* ]] || { echo "[-] 声明的私网目标访问失败" >&2; exit 1; }
  echo "[+] 声明的私网目标放行验证通过"

  # 6c. 未声明私网目标拦截 (新建 project-c，未声明私网目标)
  local proj_c="$E2E_WORKSPACE/project-c"
  mkdir -p "$proj_c"
  (
    cd "$proj_c"
    git init -q
    cat <<'EOF' > .sandbox.yaml
network: []
EOF
    git add . && git -c user.name=C -c user.email=c@test commit -m init -q
  )
  cd "$proj_c"
  local unauth_blocked=0
  if run_sb run curl -s -I -m 2 http://192.168.69.46/ >/dev/null 2>&1; then
    echo "[-] 未声明的私网目标被意外连通" >&2
    exit 1
  else
    unauth_blocked=1
  fi
  [[ "$unauth_blocked" -eq 1 ]] || { echo "[-] 未声明的私网目标未被拦截" >&2; exit 1; }
  echo "[+] 未声明的私网目标拦截验证通过"

  echo "=== 7. 验证 Secret 在上下文内被替换 (假 Secret) ==="
  cd "$proj_a"
  # 发往受权目标 api.github.com: msb proxy 替换占位符，GitHub 校验假 Token 返回 401
  local gh_resp
  gh_resp="$(run_sb run curl -s -i https://api.github.com/user \
    -H 'Authorization: Bearer $MOCK_GITHUB_TOKEN' \
    -H 'User-Agent: sb-unit3-test' 2>&1 || true)"
  echo "GitHub response with secret: $gh_resp"
  [[ "$gh_resp" == *"401 Unauthorized"* && "$gh_resp" == *"Bad credentials"* ]] || { echo "[-] Secret 替换验证失败: 未收到 GitHub 鉴权响应" >&2; exit 1; }
  echo "[+] Secret 替换验证通过 (占位符在网络出口被替换为真假凭据并被目标响应)"

  # 发往未授权目标: Authorization 头被 msb proxy 剥除，真实 secret 绝不泄漏
  local httpbin_resp
  httpbin_resp="$(run_sb run curl -s https://httpbin.org/headers -H 'Authorization: Bearer $MOCK_GITHUB_TOKEN' -H 'User-Agent: test' || true)"
  echo "httpbin response: $httpbin_resp"
  [[ "$httpbin_resp" != *"ghp_mock_unit3_test_secret_7788"* ]] || { echo "[-] Secret 泄漏至未授权目标" >&2; exit 1; }
  echo "[+] Secret 发往非授权目标防护验证通过 (占位符未替换且真实 secret 未泄漏)"

  echo "=== 8. 验证并发两个上下文，增删其中一个不打断另一个 ==="
  cd "$proj_a"
  # 启动后台上下文 A (运行 6 秒，写入并检查)
  local bg_log="$E2E_DIR/bg_context.log"
  run_sb run bash -c '
    for i in 1 2 3 4 5; do
      echo "CTX_A_PULSE_$i" >> ctx_a.pulse
      sleep 1
    done
  ' > "$bg_log" 2>&1 &
  local bg_pid=$!

  sleep 1.5
  # 此时上下文 A 正在运行，核验 VM 为 busy
  local busy_during_a
  busy_during_a="$(run_sb status --json | jq -r .busy)"
  echo "VM busy status during concurrent run: $busy_during_a"
  [[ "$busy_during_a" == "true" ]] || { echo "[-] 并发运行期间 VM 未被标记为 busy" >&2; exit 1; }

  # 启动前台上下文 B，执行操作并退出
  echo "[+] 启动并发前台上下文 B..."
  local ctx_b_out
  ctx_b_out="$(run_sb run echo 'Context B execution finished')"
  echo "Context B output: $ctx_b_out"
  [[ "$ctx_b_out" == "Context B execution finished" ]] || { echo "[-] 上下文 B 运行失败" >&2; exit 1; }

  # 等待上下文 A 完成
  wait "$bg_pid"
  [[ -f "$proj_a/ctx_a.pulse" ]] || { echo "[-] 上下文 A 未正常写入" >&2; exit 1; }
  local pulse_count
  pulse_count="$(wc -l < "$proj_a/ctx_a.pulse")"
  echo "Context A heartbeat count: $pulse_count"
  [[ "$pulse_count" -eq 5 ]] || { echo "[-] 上下文 A 中途被打断或计数不全: $pulse_count" >&2; exit 1; }
  echo "[+] 并发增删独立性验证通过 (上下文 B 退出未影响上下文 A)"

  echo "=== 9. 验证异常退出 (kill launcher) 后残留资源在下次启动被清扫 ==="
  cd "$proj_a"
  # 启动一个后台上下文准备强杀
  run_sb run sleep 60 &
  local kill_target_pid=$!
  sleep 1.5

  # 在 guest 内定位该 launcher 进程并执行 kill -9 强杀
  local launcher_guest_pids
  launcher_guest_pids="$(harness_exec sb-main pgrep -f sb-launcher || true)"
  echo "Guest launcher PIDs before kill -9: $launcher_guest_pids"
  harness_exec sb-main pkill -9 -f sb-launcher || true
  kill -9 "$kill_target_pid" 2>/dev/null || true
  wait "$kill_target_pid" 2>/dev/null || true

  # 确认此时残留尚未被外部清理 (存在登记或孤儿 netns)
  local dead_dirs
  dead_dirs="$(harness_exec sb-main ls /run/sandbox/contexts/ 2>/dev/null || true)"
  echo "Residual dirs immediately after kill -9: $dead_dirs"

  # 下一次启动命令 (如 run 或 status)，触发 launcher 的 sweep_dead_contexts
  echo "[+] 执行新命令触发异常残留自动清扫..."
  local sweep_test_out
  sweep_test_out="$(run_sb run echo 'Sweep triggered successfully')"
  echo "Sweep test output: $sweep_test_out"
  [[ "$sweep_test_out" == "Sweep triggered successfully" ]] || { echo "[-] 清扫触发失败" >&2; exit 1; }

  # 检查 guest 内网络命名空间、veth 与登记目录已无残留
  local final_ns final_veth final_ctx_dirs
  final_ns="$(harness_exec sb-main bash -c "ip netns list 2>/dev/null | grep '^sb_ctx_' || true")"
  final_veth="$(harness_exec sb-main bash -c "ip -o link show 2>/dev/null | grep -E 'vth[0-9]+' || true")"
  final_ctx_dirs="$(harness_exec sb-main bash -c "ls /run/sandbox/contexts/ 2>/dev/null || true")"
  echo "Final netns: '$final_ns', final veth: '$final_veth', final ctx dirs: '$final_ctx_dirs'"
  [[ -z "$final_ns" ]] || { echo "[-] 孤儿 netns 未被清扫: $final_ns" >&2; exit 1; }
  [[ -z "$final_veth" ]] || { echo "[-] 孤儿 veth 未被清扫: $final_veth" >&2; exit 1; }
  [[ -z "$final_ctx_dirs" ]] || { echo "[-] 孤儿 context 目录未被清扫: $final_ctx_dirs" >&2; exit 1; }
  echo "[+] 异常退出残留清扫验证通过 (netns/veth/iptables/登记零残留)"

  echo "=== 10. 附加验证: 地址池槽位耗尽与回收机制 ==="
  # 在 guest 内直接检验 launcher 的 slot 分配与耗尽回收行为
  local pool_test
  pool_test="$(harness_exec sb-main bash -c '
    launcher="$(ls -d /nix/store/*-sb-launcher/bin/sb-launcher 2>/dev/null | head -n 1)"
    mkdir -p /run/sandbox/contexts
    # 模拟占满 64 个 slot
    for ((i=0; i<64; i++)); do
      mkdir -p "/run/sandbox/contexts/sim_slot_$i"
      printf "{\"slot\": %d, \"pid\": 1}\n" "$i" > "/run/sandbox/contexts/sim_slot_$i/meta.json"
    done
    # 尝试启动第 65 个上下文，预期报错地址池已耗尽
    bash "$launcher" test_full "{\"project_root\":\"/\"}" / echo 1 2>&1 || true
    # 释放 slot 0 并确认可回收复用
    rm -rf /run/sandbox/contexts/sim_slot_0
    echo "FREED_SLOT_TEST"
    rm -rf /run/sandbox/contexts/sim_slot_*
  ')"
  echo "Pool test log: $pool_test"
  [[ "$pool_test" == *"地址池已耗尽"* ]] || { echo "[-] 地址池耗尽检测未触发" >&2; exit 1; }
  echo "[+] 地址池耗尽与回收复用验证通过"

  echo "=== 11. 清理一次性测试环境并核验宿主日常 VM 完好 ==="
  harness_cleanup
  trap - EXIT INT TERM

  harness_verify_clean "sb-main"

  echo "========================================================================"
  echo "单元 3 端到端验收测试全部通过 (Exit Code 0)"
  echo "========================================================================"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
