#!/usr/bin/env bash
# 把 OMP 插件清单落盘并与清单严格对齐。宿主激活（home.activation）与沙箱的 sb sync 共用本脚本。
#
# 目录内容每次都与清单一致：清单之外的条目一律删除。清单是唯一依据，不保留手装残留——
# 否则从清单移除的插件会永远留在 node_modules 里（80d3cc55 的做法，#129 改成只补缺后丢失）。
# 安装先落到暂存目录，装成功才整体替换，所以断网时旧目录不会被清空。
#
# 用法: install.sh <清单 package.json>
#
# 环境变量:
#   XDG_DATA_HOME          插件目录的取法与 OMP 一致（oh-my-pi packages/utils/src/dirs.ts 的 resolveIf）：
#                          $XDG_DATA_HOME/omp 存在时是 $XDG_DATA_HOME/omp/plugins，否则 ~/.omp/plugins
#   SB_BUN_CACHE_DIR       bun 下载缓存目录，默认 ~/.omp/.bun-cache
#   SB_POSTINSTALL_STRICT  非空：安装失败以非零退出（sb sync）；空：只警告（宿主激活不该因此中断）
set -euo pipefail

manifest="${1:?用法: install.sh <清单 package.json>}"

if [[ -n "${XDG_DATA_HOME:-}" && -d "$XDG_DATA_HOME/omp" ]]; then
  plugins="$XDG_DATA_HOME/omp/plugins"
else
  plugins="$HOME/.omp/plugins"
fi
bun_cache="${SB_BUN_CACHE_DIR:-$HOME/.omp/.bun-cache}"
mkdir -p "$plugins" "$bun_cache"

# Bun 对缓存里已有的 git 裸仓库只 fetch 到 FETCH_HEAD，不更新 refs/heads/main，#main 永远解析成
# 首次克隆的提交（上游缺陷 #11548）。只删 git 条目（*.git 裸仓库、@G@<sha> 提取目录）强制重新克隆，
# npm 包条目跨激活保留（a8f79454 实测 35s → 5s）。
# a8f79454 原本清理 $plugins/.bun-cache；#129 把缓存目录换成 SB_BUN_CACHE_DIR 后那行清的是不存在的
# 目录，#159 据此删除，于是 #main 跟踪能力从 #129 起就丢了。这里把清理指回实际缓存目录。
# 上游修复 oven-sh/bun#44968 已合并但未进 1.4.3；bun ≥ 1.4.4 实测后即可删掉这行。
rm -rf "$bun_cache"/*.git "$bun_cache"/@G@* 2>/dev/null || true

# 落盘的是可写副本：源文件在 /nix/store，只读
# 与清单严格对齐：结果只取决于清单，清单之外的条目一律不留。
# 不按名字挑着删：node_modules 顶层是「直接依赖 + bun 提升的传递依赖」，宿主实测 11 个直接依赖
# 对应 254 个顶层条目，按依赖名修剪会误删 243 个传递依赖。
# 也不保留手装残留：清单是唯一依据（80d3cc55 的做法，#129 改成只补缺后丢失）。
# 但删除不能先做：实测断网时 bun install 报 ConnectionClosed，先删就把宿主插件全清空，而宿主激活
# 失败只警告不中断。所以先装到暂存目录，装成功才整体替换，失败时旧目录原样保留。
staging="$(dirname "$plugins")/.plugins-staging"
rm -rf "$staging"
mkdir -p "$staging"
install -m 0644 "$manifest" "$staging/package.json"
# bun.lock 一并带过去：删掉它 bun 要重新解析版本，实测断网即 DNSResolveFailed；留着才能离线复用缓存。
if [[ -f "$plugins/bun.lock" ]]; then cp "$plugins/bun.lock" "$staging/bun.lock"; fi

# 清单里的私有依赖写成 git+ssh://git@github.com/…，bun 取包时把它解析成 ssh://git@github.com/…，
# 两种前缀都要改写，只改前一种会在 guest 里以 Permission denied (publickey) 失败。
# 宿主激活不该为 ssh 去触发 1Password 授权，guest 里没有 SSH key，所以两边都改走 https，认证交给当前环境的
# git 配置里的 credential helper（宿主：gh 登录态；沙箱：gh 读 GITHUB_TOKEN 占位符，msb 在网络边界替换为真实 token）。
# 只用环境变量设置，只作用于这一次安装，不写任何 gitconfig。
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_0=git+ssh://git@github.com/
export GIT_CONFIG_KEY_1=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_1=ssh://git@github.com/

if BUN_INSTALL_CACHE_DIR="$bun_cache" bun install --cwd "$staging" --silent; then
  # 装成功才替换：整个 node_modules 换掉，清单之外的条目连同运行时登记表一起消失。
  rm -rf "$plugins/node_modules" "$plugins/omp-plugins.lock.json"
  mv "$staging/node_modules" "$plugins/node_modules"
  install -m 0644 "$staging/package.json" "$plugins/package.json"
  if [[ -f "$staging/bun.lock" ]]; then cp "$staging/bun.lock" "$plugins/bun.lock"; fi
  rm -rf "$staging"
  exit 0
fi

rm -rf "$staging"
msg="omp 插件安装失败，插件目录可能与清单不一致: $plugins"
if [[ -n "${SB_POSTINSTALL_STRICT:-}" ]]; then
  echo "[-] 错误: $msg" >&2
  exit 1
fi
echo "[!] 警告: $msg" >&2
