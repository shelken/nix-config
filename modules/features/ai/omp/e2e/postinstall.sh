#!/usr/bin/env bash
# ==============================================================================
# 宿主激活 e2e：tool-postInstall-omp (postinstall.sh)
#
# 取已构建 Home Manager generation 里真实的 `tool-postInstall-omp` 激活片段，
# 连同 activate 头部（HM 在此重置 PATH），在隔离 HOME 里按 `just hm` 同样的
# 环境跑一遍。不下载任何东西：`bun` 的位置放一个替身，其余（PATH 解析、清单
# 同步、GitHub 改走 https、失败处理）全部真实执行。
#
# 检查安装后的插件文件、清单可写性、失败退出策略和 XDG 路径选择。
# Bun 替身按测试清单生成插件文件，不访问网络。
# 真实 HOME 的检查只解析 mise 提供的 Bun，不安装插件。
#
# 运行方式（仓库根目录执行）:
#   bash modules/features/ai/omp/e2e/postinstall.sh
#   前置: 新增文件已 git add；profile 取 HM_PROFILE 或 .host-profile 的 PROFILE；
#         第 4 项要求宿主已 `mise install` 过 bun。
# ==============================================================================
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
profile="${HM_PROFILE:-$(sed -n 's/^PROFILE=//p' "$repo/.host-profile" 2>/dev/null || true)}"
[[ -n "$profile" ]] || { echo "缺少 profile：设 HM_PROFILE 或提供 .host-profile" >&2; exit 2; }

gen="$(nix build --no-link --print-out-paths "$repo#homeConfigurations.$profile.activationPackage")"
activate="$gen/activate"
# 激活片段依赖 bash 4+ 语法：用 activate 自己 shebang 里的 bash，不能用 macOS 自带 3.2
hm_bash="$(sed -n '1s/^#!//p' "$activate")"
jq_bin="$(command -v jq)"
mv_bin="$(command -v mv)"

work="$(mktemp -d)"
trap 'rm -r "$work"' EXIT

# activate 头部到 source home-manager.sh 为止：含 set -eu、cd $HOME、重置 PATH、_iNote
header() { sed '/^source .*home-manager\.sh$/q' "$activate"; }
block() { awk '/^_iNote "Activating %s" "tool-postInstall-omp"/{f=1;next} /^_iNote "Activating/{f=0} f' "$activate"; }
[[ -n "$(block)" ]] || { echo "activate 里找不到 tool-postInstall-omp" >&2; exit 2; }

fails=0
check() { # check <描述> <命令...>
  local desc="$1"; shift
  if "$@"; then echo "PASS $desc"; else echo "FAIL $desc"; fails=$((fails + 1)); fi
}

# $1：Bun 退出码；$2：xdg / xdg-bare / 空；$3：严格模式。
run_activation() {
  home="$work/home-$1${2:+-$2}"
  layout="${2:-}"
  if [[ "$layout" == xdg ]]; then
    plugins="$home/xdg/data/omp/plugins"
    mkdir -p "$home/xdg/data/omp"
  else
    plugins="$home/.omp/plugins"
  fi
  mkdir -p "$home/.local/share/mise/shims"
  cat > "$home/manifest.json" <<'JSON'
{"dependencies":{"keep-a":"1.0.0","remove-b":"1.0.0"}}
JSON
  cat > "$home/.local/share/mise/shims/bun" <<'STUB'
#!/bin/sh
[ "${STUB_BUN_RC:-0}" = 0 ] || exit "$STUB_BUN_RC"
[ "${STUB_MODE:-}" != missing ] || exit 0
while [ "$#" -gt 0 ]; do
  if [ "$1" = --cwd ]; then shift; cwd="$1"; fi
  shift
done
mkdir -p "$cwd/node_modules"
"$STUB_JQ" -r '.dependencies | keys[]' "$cwd/package.json" | while IFS= read -r package; do
  mkdir -p "$cwd/node_modules/$package"
  printf 'installed\n' > "$cwd/node_modules/$package/installed"
done
printf 'generated-lock\n' > "$cwd/bun.lock"
STUB
  cat > "$home/.local/share/mise/shims/mv" <<'STUB'
#!/bin/sh
case "$1" in
  */.plugins-staging*) [ "${STUB_MODE:-}" != swap ] || exit 73 ;;
esac
exec "$STUB_REAL_MV" "$@"
STUB
  chmod +x "$home/.local/share/mise/shims/"{bun,mv}
  { header; block; } > "$home/activation.sh"
  activate_home "$1" "${3:-}"
}

activate_home() {
  # 不继承宿主变量，清单与所有写入都限定在隔离 HOME。
  env -i HOME="$home" ${layout:+XDG_DATA_HOME="$home/xdg/data"} \
    ${2:+SB_POSTINSTALL_STRICT=1} SB_OMP_MANIFEST="$home/manifest.json" \
    GITHUB_TOKEN=MSB_VERIFY_GITHUB_TOKEN \
    STUB_BUN_RC="$1" STUB_JQ="$jq_bin" STUB_REAL_MV="$mv_bin" STUB_MODE="${3:-}" \
    PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin \
    "$hm_bash" "$home/activation.sh" > "$home/out" 2>&1
}

installed_manifest_is_writable() {
  [[ -w "$plugins/package.json" ]]
}

installed_plugins_match_manifest() {
  [[ "$(cat "$plugins/node_modules/keep-a/installed")" == installed ]] &&
    [[ "$(cat "$plugins/node_modules/remove-b/installed")" == installed ]]
}

strict_activation_fails() {
  local rc=0
  run_activation 1 "" strict || rc=$?
  [[ "$rc" -ne 0 ]] && grep -q '错误' "$home/out"
}

activation_warns_and_continues() {
  local rc=0
  run_activation 1 || rc=$?
  [[ "$rc" -eq 0 ]] && grep -q '警告' "$home/out"
}

sandbox_layout_installs_under_xdg() {
  run_activation 0 xdg &&
    installed_plugins_match_manifest &&
    installed_manifest_is_writable &&
    [[ ! -e "$home/.omp/plugins" ]]
}

xdg_without_omp_dir_installs_under_home() {
  run_activation 0 xdg-bare && installed_plugins_match_manifest
}

unchanged_manifest_repairs_plugins() {
  run_activation 0 || return 1
  rm -rf "$plugins/node_modules/keep-a"
  mkdir -p "$plugins/node_modules/hand-installed"
  printf 'old-registry\n' > "$plugins/omp-plugins.lock.json"
  activate_home 0 || return 1
  installed_plugins_match_manifest &&
    [[ ! -e "$plugins/node_modules/hand-installed" ]] &&
    [[ ! -e "$plugins/omp-plugins.lock.json" ]]
}

removed_dependency_is_cleaned() {
  run_activation 0 || return 1
  printf '{"dependencies":{"keep-a":"1.0.0"}}\n' > "$home/manifest.json"
  activate_home 0 || return 1
  [[ "$(cat "$plugins/node_modules/keep-a/installed")" == installed ]] &&
    [[ ! -e "$plugins/node_modules/remove-b" ]]
}

failed_update_preserves_state() {
  local mode="$1" strict="${2:-}" rc=0 bun_rc=0 snapshot
  run_activation 0 || return 1
  printf 'old-registry\n' > "$plugins/omp-plugins.lock.json"
  snapshot="$home/before-$mode${strict:+-strict}"
  cp -R "$plugins" "$snapshot"
  printf '{"dependencies":{"keep-a":"2.0.0"}}\n' > "$home/manifest.json"
  [[ "$mode" != install ]] || bun_rc=1
  activate_home "$bun_rc" "$strict" "$mode" || rc=$?
  diff -r "$snapshot" "$plugins" > /dev/null || return 1
  if [[ -n "$strict" ]]; then
    [[ "$rc" -ne 0 ]] && grep -q '错误' "$home/out"
  else
    [[ "$rc" -eq 0 ]] && grep -q '警告' "$home/out"
  fi
}

real_mise_bun_resolves() {
  local probe="$work/probe.sh"
  { header; block | sed -n '/^export PATH=/{p;q;}'; echo 'command -v bun >/dev/null && bun --version >/dev/null'; } > "$probe"
  env -i HOME="$HOME" PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin "$hm_bash" "$probe"
}

check "激活成功退出" run_activation 0
check "暂存安装的插件文件进入最终目录" installed_plugins_match_manifest
check "落盘的 package.json 可写" installed_manifest_is_writable
check "清单未变：恢复缺失插件并删除额外插件和登记表" unchanged_manifest_repairs_plugins
check "清单移除依赖：保留其余插件并删除移除的插件" removed_dependency_is_cleaned
for failure in install missing swap; do
  check "$failure 失败：宿主保留完整旧状态并继续激活" failed_update_preserves_state "$failure"
  check "$failure 失败：沙箱保留完整旧状态并返回非零" failed_update_preserves_state "$failure" strict
done
check "沙箱严格模式：bun 失败时返回非零并打印错误" strict_activation_fails
check "bun 失败时激活返回 0 且打印警告" activation_warns_and_continues
check "沙箱布局：插件装到 \$XDG_DATA_HOME/omp/plugins，不碰 ~/.omp/plugins" sandbox_layout_installs_under_xdg
check "XDG_DATA_HOME 已设但无 omp 目录：仍装到 ~/.omp/plugins" xdg_without_omp_dir_installs_under_home
check "真实 HOME：激活 PATH 能解析到 mise 的 bun" real_mise_bun_resolves

if [[ "$fails" -ne 0 ]]; then echo "$fails 项失败"; exit 1; fi
echo "全部通过"
