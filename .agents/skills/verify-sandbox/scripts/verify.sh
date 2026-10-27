#!/usr/bin/env bash
set -euo pipefail

REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
RUN_ID="${SB_VERIFY_RUN:-default}"
HOST="${SB_VERIFY_HOST:-mio}"
# 用 /tmp 而非 macOS 的 TMPDIR：后者太长，msb 的 Unix socket 路径会超过 104 字节上限；
# realpath 去掉 /tmp -> /private/tmp 的符号链接，msb 拒绝挂载符号链接路径
BASE="$(realpath /tmp)/sb-verify/$RUN_ID"
WORK="$BASE/work"
EVIDENCE="$BASE/evidence"
# 测试项目必须在 sb.yaml 的挂载根内
PROJ="$HOME/Code/sb-verify-$RUN_ID"
MSB_BIN="$(mise which msb 2>/dev/null || command -v msb)"

die() { echo "[-] $*" >&2; exit 1; }

sb_bin() {
  [[ -x "$WORK/gen/home-path/bin/sb" ]] || die "未 setup：先运行 verify.sh setup"
  readlink -f "$WORK/gen/home-path/bin/sb"
}

# 会话里继承的 MSB_CONFIG_PATH 指向日常配置，其中的 home 字段会覆盖 MSB_HOME，必须同时替换
iso_env() {
  env SB_SANDBOX_CONFIG="$WORK/sbcfg" SB_CONFIG="$WORK/sb.yaml" \
    MSB_HOME="$WORK/msb" MSB_CONFIG_PATH="$WORK/msb.json" "$@"
}

cmd_setup() {
  mkdir -p "$WORK/msb" "$EVIDENCE"
  echo "[*] 构建 $HOST 的 Home Manager 产物（out-link 作为 GC root，防止验证中途被回收）"
  # liveEdit 会把声明的配置软链到主工作区，验证的就不是当前 worktree；构建时强制关掉
  nix build --impure --out-link "$WORK/gen" --expr "
    let
      flake = builtins.getFlake \"$REPO\";
      sys = flake.darwinConfigurations.$HOST or flake.nixosConfigurations.$HOST;
      user = flake.homeConfigurations.$HOST.config.home.username;
    in
    (sys.extendModules {
      modules = [ ({ lib, ... }: { home-manager.users.\${user}.shelken.dotfiles.liveEdit = lib.mkForce false; }) ];
    }).config.home-manager.users.\${user}.home.activationPackage"

  sed "s/^memory: .*/memory: \"${SB_VERIFY_MEMORY:-4G}\"/" "$REPO/modules/features/ai/sandbox/sb.yaml" > "$WORK/sb.yaml"

  local cache
  cache="$(realpath "$HOME/.cache/microsandbox")"
  cat > "$WORK/msb.json" <<EOF
{"version":1,"home":"$WORK/msb","paths":{"cache":"$cache"},"sandbox_defaults":{"metrics_sample_interval_ms":0,"disable_metrics_sample":true}}
EOF

  # 激活时的发布脚本写宿主 ~/.config/sandbox；改写目标到隔离目录，不碰日常 VM 在用的配置
  local publish
  publish="$(grep -o '/nix/store/[a-z0-9]*-publish-sandbox-config' "$WORK/gen/activate" | head -n 1)"
  [[ -n "$publish" ]] || die "激活脚本里找不到 publish-sandbox-config，沙箱是否已为 $HOST 启用"
  SANDBOX_CONFIG_DIR="$WORK/sbcfg" "$publish"

  if [[ ! -d "$PROJ/.git" ]]; then
    mkdir -p "$PROJ"
    git -C "$PROJ" init -q
    echo "sb verify $RUN_ID" > "$PROJ/README.md"
    git -C "$PROJ" add README.md
    git -C "$PROJ" -c user.name=verify -c user.email=verify@localhost commit -q -m init
  fi
  echo "[+] setup 完成：WORK=$WORK PROJ=$PROJ EVIDENCE=$EVIDENCE"
}

cmd_doctor() {
  local ok=1
  check() { if eval "$2" >/dev/null 2>&1; then echo "[+] $1"; else echo "[-] $1"; ok=0; fi; }
  check "msb 0.7.7 可用" "'$MSB_BIN' --version | grep -q 0.7.7"
  check "sec-run 可用（真实凭据注入）" "command -v sec-run"
  check "共用 mise 目录存在" "test -d '$HOME/Data/sandboxes/mise/aarch64-linux'"
  check "已 setup：sb 可执行且受 GC root 保护" "test -x '$WORK/gen/home-path/bin/sb'"
  check "隔离配置已发布（含 sync-guest.sh）" "test -f '$WORK/sbcfg/current/sync-guest.sh'"
  check "测试项目在挂载根内" "test -d '$PROJ/.git'"
  check "msb 配置的 home 指向隔离目录" "jq -e --arg h '$WORK/msb' '.home == \$h' '$WORK/msb.json'"
  check "Linux 构建器可用" "nix build --no-link --impure --expr '(builtins.getFlake \"nixpkgs\").legacyPackages.aarch64-linux.runCommand \"probe-\${toString builtins.currentTime}\" {} \"uname -m > \$out\"'"
  [[ "$ok" -eq 1 ]] || die "doctor 未通过，不要继续驱动"
}

cmd_sb() { cd "$PROJ" && iso_env "$(sb_bin)" "$@"; }
cmd_msb() { iso_env "$MSB_BIN" "$@"; }

cmd_run() {
  local name="$1"; shift
  [[ "${1:-}" == "--" ]] && shift
  mkdir -p "$EVIDENCE"
  printf '%q ' "$@" > "$EVIDENCE/$name.cmd"
  local rc=0
  (cd "$PROJ" && "$@") > "$EVIDENCE/$name.out" 2> "$EVIDENCE/$name.err" || rc=$?
  echo "$rc" > "$EVIDENCE/$name.rc"
  echo "[evidence] $name rc=$rc -> $EVIDENCE/$name.{cmd,out,err,rc}"
  return 0
}

cmd_smoke() {
  cmd_run smoke -- env SB_BIN="$(sb_bin)" bash "$REPO/modules/features/ai/sandbox/e2e/smoke.sh"
  tail -n 3 "$EVIDENCE/smoke.out"
}

cmd_cleanup() {
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    cmd_msb stop "$name" >/dev/null 2>&1 || true
    cmd_msb rm --force "$name" >/dev/null 2>&1 || true
  done < <(cmd_msb ls --format json 2>/dev/null | jq -r '.[].name // empty')
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    cmd_msb volume rm "$name" >/dev/null 2>&1 || true
  done < <(cmd_msb volume ls --format json 2>/dev/null | jq -r '.[].name // empty')
  [[ -d "$WORK" ]] && rm -r "$WORK"
  [[ -d "$PROJ" ]] && rm -r "$PROJ"
  echo "[+] 已清理 VM、卷、工作目录与测试项目；证据保留在 $EVIDENCE"
}

case "${1:-}" in
  setup) cmd_setup ;;
  doctor) cmd_doctor ;;
  sb) shift; cmd_sb "$@" ;;
  msb) shift; cmd_msb "$@" ;;
  run) shift; cmd_run "$@" ;;
  smoke) cmd_smoke ;;
  cleanup) cmd_cleanup ;;
  paths) echo "WORK=$WORK"; echo "PROJ=$PROJ"; echo "EVIDENCE=$EVIDENCE"; echo "SB=$(sb_bin 2>/dev/null || echo 未setup)" ;;
  *) die "用法: verify.sh setup|doctor|sb <args>|msb <args>|run <名字> -- <命令>|smoke|cleanup|paths" ;;
esac
