#!/usr/bin/env bash
# 把仓库里的 OMP 插件清单补装到 OMP 读取的插件目录，只补缺，不删除目录里已有的依赖。
# 宿主激活（home.activation）与沙箱的 sb sync 共用本脚本。
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
mkdir -p "$plugins/node_modules" "$bun_cache"

# 落盘的是可写副本：源文件在 /nix/store，只读
install -m 0644 "$manifest" "$plugins/package.json"

# 清单里的私有依赖写成 git+ssh://git@github.com/…，bun 取包时把它解析成 ssh://git@github.com/…，
# 两种前缀都要改写，只改前一种会在 guest 里以 Permission denied (publickey) 失败。
# 宿主激活不该为 ssh 去触发 1Password 授权，guest 里没有 SSH key，所以两边都改走 https，认证交给当前环境的
# git 配置里的 credential helper（宿主：gh 登录态；沙箱：gh 读 GITHUB_TOKEN 占位符，msb 在网络边界替换为真实 token）。
# 只用环境变量设置，只作用于这一次安装，不写任何 gitconfig。
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_0=git+ssh://git@github.com/
export GIT_CONFIG_KEY_1=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_1=ssh://git@github.com/

if BUN_INSTALL_CACHE_DIR="$bun_cache" bun install --cwd "$plugins" --silent; then
  exit 0
fi

msg="omp 插件安装失败，插件目录可能与清单不一致: $plugins"
if [[ -n "${SB_POSTINSTALL_STRICT:-}" ]]; then
  echo "[-] 错误: $msg" >&2
  exit 1
fi
echo "[!] 警告: $msg" >&2
