#!/usr/bin/env bash
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

find_msb
E2E_DIR="$(resolve "$(mktemp -d /tmp/sb-smoke-XXXXXX)")"
E2E_MSB_HOME="$E2E_DIR/msb-home"
E2E_MSB_CONFIG="$E2E_DIR/microsandbox-config.json"
mkdir -p "$E2E_MSB_HOME"

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

WS="$E2E_DIR/workspace"
mkdir -p "$WS"
WS="$(resolve "$WS")"
PROJ_A="$WS/project-a"
PROJ_B="$WS/project-b"
WORKTREE="$WS/project-a-worktree"
mkdir -p "$PROJ_A" "$PROJ_B"

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
    - "private"
EOF

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
    "$REPO_ROOT#homeConfigurations.mio.config.home.activationPackage" || true)"
  if [[ -n "$app_dir" && -x "$app_dir/home-path/bin/sb" ]]; then
    SB_BIN="$(readlink -f "$app_dir/home-path/bin/sb")"
  else
    echo "[-] 无法构建/定位 sb 产物 (可设置 SB_BIN 覆盖): ${app_dir:-无输出}" >&2
    exit 1
  fi
fi
echo "[+] sb: $SB_BIN"
echo "[+] 临时隔离环境: $E2E_DIR"

REAL_CONFIG="${SB_TEST_CONFIG:-$(grep -o '/nix/store/[a-z0-9]*-sb-config.json' "$SB_BIN" | head -n 1)}"
[[ -n "$REAL_CONFIG" ]] || { echo "[-] 在 $SB_BIN 里找不到 sb-config.json" >&2; exit 1; }

MISE_HOST_DIR="$(resolve "$(jq -r .mise.host_dir "$REAL_CONFIG")")"
if [[ ! -d "$MISE_HOST_DIR" ]]; then
  echo "[-] 共用 mise 目录不存在: $MISE_HOST_DIR" >&2
  exit 1
fi

CFG_DIR="$E2E_DIR/sandbox-config"
mkdir -p "$CFG_DIR/current"
: > "$CFG_DIR/current/declared-paths"
: > "$CFG_DIR/current/writable-roots"

SB_E2E_CONFIG="$E2E_DIR/sb-config.json"
jq --arg policy "$TEST_YAML" --arg publish "$CFG_DIR" --arg lock "$E2E_DIR/sync.lock" \
  '.policy_yaml = $policy | .publish_dir = $publish | .sync_lock = $lock | .guest_sync = "/dev/null" | .host_credentials = false' \
  "$REAL_CONFIG" > "$SB_E2E_CONFIG"

run_sb() {
  MSB_CONFIG_PATH="$E2E_MSB_CONFIG" \
    MSB_HOME="$E2E_MSB_HOME" \
    SB_TEST_CONFIG="$SB_E2E_CONFIG" \
    "$SB_BIN" "$@"
}

(cd "$PROJ_A" && run_sb trust >/dev/null)


echo "=== 1/3 相邻项目不可见 ==="
vis="$(cd "$PROJ_A" && run_sb run bash -c \
  "if [[ -e '$PROJ_B' ]]; then echo FOUND; else echo NOT_FOUND; fi")"
if [[ "$vis" != "NOT_FOUND" ]]; then
  echo "[-] 隔离穿透: 上下文内可见相邻项目 $PROJ_B (输出: $vis)" >&2
  exit 1
fi
echo "[+] 项目 A 上下文内看不到相邻项目 B"

echo "=== 2/3 未声明的私网目标不可达 (应用层断言) ==="
# msb 会伪响应 TCP 握手，ping 与 TCP 连通性都不可信；只能以是否收到 HTTP 响应行判定
blocked="$(cd "$PROJ_A" && run_sb run curl -s -i -m 3 http://192.168.69.46/ 2>&1 || true)"
if [[ "$blocked" == *"HTTP/"* ]]; then
  echo "[-] 未声明的私网目标收到了应用层 HTTP 响应:" >&2
  echo "$blocked" >&2
  exit 1
fi
echo "[+] 未声明的私网目标无应用层响应 (curl 输出: ${blocked:-空})"

echo "=== 3/3 worktree 内 git commit ==="
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
echo "[+] worktree 内 git commit 成功且提交同步回宿主"

echo "[+] 隔离边界冒烟测试全部通过"
