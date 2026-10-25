#!/usr/bin/env bash
# ==============================================================================
# 宿主激活 e2e：tool-postInstall-omp (postinstall.sh)
#
# 取已构建 Home Manager generation 里真实的 `tool-postInstall-omp` 激活片段，
# 连同 activate 头部（HM 在此重置 PATH），在隔离 HOME 里按 `just hm` 同样的
# 环境跑一遍。不下载任何东西：`bun` 的位置放一个替身，其余（PATH 解析、清单
# 同步、私有插件改写、失败处理）全部真实执行。
#
# 断言：
#   1. 激活 PATH 下 `bun` 可被找到，且以隔离的插件目录为 --cwd、带
#      --ignore-scripts 被调用（过去 PATH 被 HM 重置，bun 找不到，错误被吞）
#   2. 安装前落盘的 package.json 与仓库清单一致：每个 npm 依赖原样保留，
#      每个 git 依赖改写成 file: 指向 .git-vendor，不多不少
#   3. bun 失败时激活仍返回 0，但必须打印警告（失败不得静默）
#   4. 真实 HOME 下，激活 PATH 能解析到 mise 提供的真实 bun（只读，不安装）
#   5. 沙箱布局（XDG_DATA_HOME/omp 存在）：插件装到 $XDG_DATA_HOME/omp/plugins，
#      不碰 ~/.omp/plugins（过去恒装到后者，OMP 读前者，沙箱内零插件）；
#      XDG_DATA_HOME 已设但 omp 目录不存在（宿主）：仍装到 ~/.omp/plugins
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
manifest="$repo/modules/features/ai/omp/plugins/package.json"

gen="$(nix build --no-link --print-out-paths "$repo#homeConfigurations.$profile.activationPackage")"
activate="$gen/activate"
# 激活片段依赖 bash 4+ 语法：用 activate 自己 shebang 里的 bash，不能用 macOS 自带 3.2
hm_bash="$(sed -n '1s/^#!//p' "$activate")"

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

# 在隔离 HOME 里跑一次激活；$1 = 替身 bun 的退出码；$2 = 布局：
#   空        宿主：不设 XDG_DATA_HOME
#   xdg       沙箱：XDG_DATA_HOME 已设且 $XDG_DATA_HOME/omp 已存在
#   xdg-bare  XDG_DATA_HOME 已设但 $XDG_DATA_HOME/omp 不存在（本机宿主的真实状态）
# 输出落 $home/out，插件目录落 $plugins，返回激活的退出码
run_activation() {
  home="$work/home-$1${2:+-$2}"
  if [[ "${2:-}" == xdg ]]; then
    plugins="$home/xdg/data/omp/plugins"
    mkdir -p "$home/xdg/data/omp"
  else
    plugins="$home/.omp/plugins"
  fi
  mkdir -p "$home/.local/share/mise/shims"
  cat > "$home/.local/share/mise/shims/bun" <<'STUB'
#!/bin/sh
printf '%s\t%s\n' "$BUN_INSTALL_CACHE_DIR" "$*" >> "$HOME/bun.calls"
exit "${STUB_BUN_RC:-0}"
STUB
  chmod +x "$home/.local/share/mise/shims/bun"
  # 私有插件副本预置成"已 clone 且 ref 一致"，激活走复用分支，不触网
  jq -r '.dependencies | to_entries[] | select(.value | test("^(git\\+|git@|ssh://)"))
         | [.key, (.value | capture("#(?<r>.+)$").r)] | @tsv' "$manifest" |
    while IFS=$'\t' read -r name ref; do
      mkdir -p "$plugins/.git-vendor/$name"
      printf '%s\n' "$ref" > "$plugins/.git-vendor/$name/.ref"
    done
  { header; block; } > "$home/activation.sh"
  # env -i：不继承用户的 XDG_DATA_HOME 等变量，否则激活会落到真实插件目录
  env -i HOME="$home" ${2:+XDG_DATA_HOME="$home/xdg/data"} STUB_BUN_RC="$1" PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin \
    "$hm_bash" "$home/activation.sh" > "$home/out" 2>&1
}

installed_manifest_matches_repo() {
  jq -e --slurpfile got "$plugins/package.json" --arg vendor "$plugins/.git-vendor" '
    .dependencies as $want
    | $got[0].dependencies as $have
    | ($want | keys) == ($have | keys)
      and ($want | to_entries | all(
          if (.value | test("^(git\\+|git@|ssh://)"))
          then $have[.key] == "file:\($vendor)/\(.key)"
          else $have[.key] == .value end))
  ' "$manifest" > /dev/null
}

bun_called_once_in_plugins_dir() {
  [[ "$(wc -l < "$home/bun.calls")" -eq 1 ]] &&
    grep -q -- "--cwd $plugins .*--ignore-scripts" "$home/bun.calls"
}

activation_warns_and_continues() {
  local rc=0
  run_activation 1 || rc=$?
  [[ "$rc" -eq 0 ]] && [[ -s "$home/bun.calls" ]] && grep -q '警告' "$home/out"
}

sandbox_layout_installs_under_xdg() {
  run_activation 0 xdg &&
    bun_called_once_in_plugins_dir &&
    installed_manifest_matches_repo &&
    [[ ! -e "$home/.omp/plugins" ]]
}

xdg_without_omp_dir_installs_under_home() {
  run_activation 0 xdg-bare && bun_called_once_in_plugins_dir
}

real_mise_bun_resolves() {
  local probe="$work/probe.sh"
  { header; block | sed -n '/^export PATH=/{p;q;}'; echo 'command -v bun >/dev/null && bun --version >/dev/null'; } > "$probe"
  env -i HOME="$HOME" PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin "$hm_bash" "$probe"
}

check "激活成功退出" run_activation 0
check "bun 以隔离插件目录为 --cwd、带 --ignore-scripts 被调用一次" bun_called_once_in_plugins_dir
check "落盘的 package.json 与仓库清单一致（npm 原样，git 改 file:）" installed_manifest_matches_repo
check "bun 失败时激活返回 0 且打印警告" activation_warns_and_continues
check "沙箱布局：插件装到 \$XDG_DATA_HOME/omp/plugins，不碰 ~/.omp/plugins" sandbox_layout_installs_under_xdg
check "XDG_DATA_HOME 已设但无 omp 目录：仍装到 ~/.omp/plugins" xdg_without_omp_dir_installs_under_home
check "真实 HOME：激活 PATH 能解析到 mise 的 bun" real_mise_bun_resolves

if [[ "$fails" -ne 0 ]]; then echo "$fails 项失败"; exit 1; fi
echo "全部通过"
