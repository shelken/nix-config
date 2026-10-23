#!/usr/bin/env bash
# ==============================================================================
# Agent 沙箱隔离边界冒烟测试 (smoke.sh)
#
# 单文件最小 harness，只保留四项隔离边界断言（其余端到端验证不维护自动化
# 套件，在单元 6 切换时手动做一次）:
#   1. 项目 A 上下文内看不到相邻项目 B（bubblewrap 只绑定当前项目）。
#   2. 未声明的私网目标不可达（应用层断言：msb 会伪响应 TCP 握手，必须以
#      「是否收到 HTTP 响应行」判定，不能用 ping/TCP 连通性）。
#   3. 假 secret 在上下文内被网络边界替换（占位符发往 api.github.com，
#      被目标以 401 Bad credentials 拒绝，证明替换真实发生）。
#   4. worktree 内 git status 与 git commit 成功（common dir 自动加绑）。
#
# 运行方式（仓库根目录执行）:
#   bash modules/features/ai/sandbox/e2e/smoke.sh
#   前置: 宿主有 msb 与 ubuntu 镜像缓存、共用 mise 目录存在、可访问公网；
#         默认现场构建 sb，可用 SB_BIN=<sb路径> 覆盖跳过构建。
#
# 硬约束（与被替换的旧 e2e 套件一致）:
#   - 一次性 MSB_HOME（mktemp 后取真实路径），绝不触碰日常 VM sb-default；
#     绝不全局 export MSB_HOME，msb 只以单命令前缀执行。
#   - 共用 mise 目录只挂载、绝不写入/移动/删除：SB_SANDBOX_CONFIG 指向空
#     目录，首次建 VM 的自动 sb sync 因找不到 sync-guest.sh 而跳过（上下文
#     PATH 回落到 launcher 内置的 bash/coreutils/git/curl，无需 mise 工具）；
#     SB_MISE_LOCK_DIR 指向临时目录，不在共用层创建锁文件。
#   - SB_NO_HOST_CREDENTIALS=1 禁止 sec-run 注入宿主真实凭据；secret 断言
#     只用纯假值。
# ==============================================================================
set -euo pipefail

E2E_DIR=""
E2E_MSB_HOME=""
E2E_MSB_CONFIG=""
MSB_BIN=""

# macOS /tmp 是指向 /private/tmp 的符号链接，msb 拒绝挂载符号链接路径
resolve() { realpath "$1"; }

find_msb() {
  if command -v mise >/dev/null 2>&1 && mise which msb >/dev/null 2>&1; then
    MSB_BIN="$(mise which msb)"
  else
    MSB_BIN="$(command -v msb)"
  fi
  if [[ -z "$MSB_BIN" || ! -x "$MSB_BIN" ]]; then
    echo "[-] 未找到 msb 可执行文件" >&2
    return 1
  fi
}

# 幂等清理: 停止并删除隔离 MSB_HOME 内的 VM 与卷，删除临时目录。
# 只经隔离 MSB_HOME 操作 msb，绝不按进程名清理（日常主 VM 同名 sb-main，
# 按名 kill 会误伤日常环境）。
cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  if [[ -n "$E2E_MSB_CONFIG" && -f "$E2E_MSB_CONFIG" && -n "$MSB_BIN" && -x "$MSB_BIN" ]]; then
    local name
    while IFS= read -r name; do
      if [[ -n "$name" ]]; then
        echo "[*] 清理沙箱: $name" >&2
        MSB_CONFIG_PATH="$E2E_MSB_CONFIG" MSB_HOME="$E2E_MSB_HOME" \
          "$MSB_BIN" stop "$name" >/dev/null 2>&1 || true
        MSB_CONFIG_PATH="$E2E_MSB_CONFIG" MSB_HOME="$E2E_MSB_HOME" \
          "$MSB_BIN" rm --force "$name" >/dev/null 2>&1 || true
      fi
    done < <(MSB_CONFIG_PATH="$E2E_MSB_CONFIG" MSB_HOME="$E2E_MSB_HOME" \
      "$MSB_BIN" ls --format json 2>/dev/null | jq -r '.[].name // empty' 2>/dev/null || true)
    while IFS= read -r name; do
      if [[ -n "$name" ]]; then
        echo "[*] 清理卷: $name" >&2
        MSB_CONFIG_PATH="$E2E_MSB_CONFIG" MSB_HOME="$E2E_MSB_HOME" \
          "$MSB_BIN" volume rm "$name" >/dev/null 2>&1 || true
      fi
    done < <(MSB_CONFIG_PATH="$E2E_MSB_CONFIG" MSB_HOME="$E2E_MSB_HOME" \
      "$MSB_BIN" volume ls --format json 2>/dev/null | jq -r '.[].name // empty' 2>/dev/null || true)
  fi
  if [[ -n "$E2E_DIR" && -d "$E2E_DIR" ]]; then
    rm -rf "$E2E_DIR"
  fi
  return "$rc"
}
trap cleanup EXIT INT TERM HUP

# ------------------------------------------------------------------------------
# 1. 一次性隔离环境: MSB_HOME、msb 全局配置、假工作区、全局上限 YAML
# ------------------------------------------------------------------------------
find_msb
E2E_DIR="$(resolve "$(mktemp -d /tmp/sb-smoke-XXXXXX)")"
E2E_MSB_HOME="$E2E_DIR/msb-home"
E2E_MSB_CONFIG="$E2E_DIR/microsandbox-config.json"
mkdir -p "$E2E_MSB_HOME"

# 复用宿主镜像缓存（realpath 规避符号链接），关闭 metrics 采样
host_cache="$HOME/.cache/microsandbox"
if [[ -d "$host_cache" ]]; then
  host_cache="$(resolve "$host_cache")"
fi
cat > "$E2E_MSB_CONFIG" <<EOF
{
  "version": 1,
  "home": "$E2E_MSB_HOME",
  "paths": { "cache": "$host_cache" },
  "sandbox_defaults": {
    "metrics_sample_interval_ms": 0,
    "disable_metrics_sample": true
  }
}
EOF

# 共用 mise 目录: 只挂载、绝不写入（缺失即失败，绝不代建）
MISE_HOST_DIR="$(resolve "${SB_MISE_HOST_DIR:-$HOME/Data/sandboxes/mise/aarch64-linux}")"
if [[ ! -d "$MISE_HOST_DIR" ]]; then
  echo "[-] 共用 mise 目录不存在: $MISE_HOST_DIR" >&2
  exit 1
fi

# 空沙箱配置目录: 让首次建 VM 的自动 sync 找不到 sync-guest.sh 而跳过
CFG_DIR="$E2E_DIR/empty-sandbox-config"
mkdir -p "$CFG_DIR/current"

# 假工作区: 相邻项目 A（git 仓库 + worktree）与 B（不可见对照）
WS="$E2E_DIR/workspace"
mkdir -p "$WS"
WS="$(resolve "$WS")"
PROJ_A="$WS/project-a"
PROJ_B="$WS/project-b"
WORKTREE="$WS/project-a-worktree"
mkdir -p "$PROJ_A" "$PROJ_B"

# 项目 A 不声明任何私网目标（network: []），断言 2 的目标对其即「未声明」
echo "# smoke project a" > "$PROJ_A/README.md"
printf 'network: []\n' > "$PROJ_A/.sandbox.yaml"
echo "ADJACENT_PROJECT_B_PRIVATE" > "$PROJ_B/private.txt"

git_host=(-c user.name=SmokeTest -c user.email=smoke@test.local)
(
  cd "$PROJ_A"
  git init -q
  git "${git_host[@]}" add .
  git "${git_host[@]}" commit -qm "init"
  git branch smoke-wt
  git worktree add -q "$WORKTREE" smoke-wt
)

# 全局能力上限: 允许 192.168.69.46（项目未声明则上下文仍拦截）；secret 只用假值
TEST_YAML="$E2E_DIR/sb.yaml"
cat > "$TEST_YAML" <<EOF
image: "ubuntu"
cpus: 2
memory: "2G"
volume:
  name: "smoke-vol"
  size: "1G"
mount_roots:
  - "$WS"
network:
  policy: "public"
  allow:
    - "public"
    - "dns"
    - "192.168.69.46"
secrets:
  MOCK_GITHUB_TOKEN:
    allow:
      - "api.github.com"
EOF

# ------------------------------------------------------------------------------
# 2. 定位 sb: 优先 SB_BIN 覆盖，否则构建一次 Home Manager 产物
# ------------------------------------------------------------------------------
REPO_ROOT="$(dirname "${BASH_SOURCE[0]}")"
while [[ ! -e "$REPO_ROOT/flake.nix" && "$REPO_ROOT" != "/" ]]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done
if [[ ! -e "$REPO_ROOT/flake.nix" ]]; then
  echo "[-] 未找到 flake.nix 仓库根 (可设置 SB_BIN 覆盖跳过构建)" >&2
  exit 1
fi
if [[ -z "${SB_BIN:-}" || ! -x "${SB_BIN:-}" ]]; then
  app_dir="$(nix build --no-link --print-out-paths \
    "$REPO_ROOT#homeConfigurations.mio.config.home.activationPackage" 2>&1 | head -n 1 || true)"
  if [[ -n "$app_dir" && -x "$app_dir/home-path/bin/sb" ]]; then
    SB_BIN="$(readlink -f "$app_dir/home-path/bin/sb")"
  else
    echo "[-] 无法构建/定位 sb 产物 (可设置 SB_BIN 覆盖):" >&2
    echo "$app_dir" >&2
    exit 1
  fi
fi
echo "[+] sb: $SB_BIN"
echo "[+] 临时隔离环境: $E2E_DIR"

# 统一入口: 隔离环境变量 + 假凭据 + 禁用宿主凭据注入（绝不读取真实密钥）
run_sb() {
  MSB_CONFIG_PATH="$E2E_MSB_CONFIG" \
    MSB_HOME="$E2E_MSB_HOME" \
    SB_CONFIG="$TEST_YAML" \
    SB_SANDBOX_CONFIG="$CFG_DIR" \
    SB_MISE_HOST_DIR="$MISE_HOST_DIR" \
    SB_MISE_LOCK_DIR="$E2E_DIR/locks" \
    SB_NO_HOST_CREDENTIALS=1 \
    MOCK_GITHUB_TOKEN="ghp_smoke_fake_secret_placeholder" \
    "$SB_BIN" "$@"
}

# ------------------------------------------------------------------------------
# 3. 四项隔离边界断言（任一失败即非零退出，EXIT trap 兜底清理）
# ------------------------------------------------------------------------------

echo "=== 1/4 相邻项目不可见 ==="
vis="$(cd "$PROJ_A" && run_sb run bash -c \
  "if [[ -e '$PROJ_B' ]]; then echo FOUND; else echo NOT_FOUND; fi")"
if [[ "$vis" != "NOT_FOUND" ]]; then
  echo "[-] 隔离穿透: 上下文内可见相邻项目 $PROJ_B (输出: $vis)" >&2
  exit 1
fi
echo "[+] 项目 A 上下文内看不到相邻项目 B"

echo "=== 2/4 未声明的私网目标不可达 (应用层断言) ==="
blocked="$(cd "$PROJ_A" && run_sb run curl -s -i -m 3 http://192.168.69.46/ 2>&1 || true)"
if [[ "$blocked" == *"HTTP/"* ]]; then
  echo "[-] 未声明的私网目标收到了应用层 HTTP 响应:" >&2
  echo "$blocked" >&2
  exit 1
fi
echo "[+] 未声明的私网目标无应用层响应 (curl 输出: ${blocked:-空})"

echo "=== 3/4 假 secret 在网络边界被替换 ==="
gh="$(cd "$PROJ_A" && run_sb run curl -s -i -m 10 https://api.github.com/user \
  -H 'Authorization: Bearer $MOCK_GITHUB_TOKEN' \
  -H 'User-Agent: sb-smoke-test' 2>&1 || true)"
if [[ "$gh" != *"401 Unauthorized"* || "$gh" != *"Bad credentials"* ]]; then
  echo "[-] Secret 替换断言失败 (未收到 GitHub 对假凭据的 401 拒绝):" >&2
  echo "$gh" >&2
  exit 1
fi
echo "[+] 占位符在出口被替换为假 secret 并被目标 401 拒绝"

echo "=== 4/4 worktree 内 git status 与 git commit ==="
(cd "$WORKTREE" && run_sb run git status --short)
(cd "$WORKTREE" && run_sb run bash -c "
  echo worktree_smoke_data >> smoke-file.txt
  git add smoke-file.txt
  git -c user.name=SmokeCtx -c user.email=ctx@smoke.local commit -qm 'commit from smoke worktree'
")
last_commit="$(git -C "$WORKTREE" log -1 --pretty=%s)"
if [[ "$last_commit" != "commit from smoke worktree" ]]; then
  echo "[-] worktree 提交未落到宿主仓库 (最后提交: $last_commit)" >&2
  exit 1
fi
echo "[+] worktree 内 git status / git commit 成功且提交同步回宿主"

echo "[+] 隔离边界冒烟测试全部通过"
