#!/usr/bin/env bash
# 每次按清单重建 OMP 插件。宿主激活与沙箱 sb sync 共用本脚本。
# 安装先使用同级暂存目录；替换前备份整个插件目录，替换失败时恢复旧状态。
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

# 不清 bun 缓存里的 git 条目：每次清都会让私有依赖重新 clone，网络一抖就整次失败。
# 需要重新解析 #main 时删 $plugins/bun.lock。

# 清单里的私有依赖写成 git+ssh://git@github.com/…，bun 取包时把它解析成 ssh://git@github.com/…，
# 两种前缀都要改写，只改前一种会在 guest 里以 Permission denied (publickey) 失败。
# 宿主激活不该为 ssh 去触发 1Password 授权，guest 里没有 SSH key，所以两边都改走 https，认证交给当前环境的
# git 配置里的 credential helper（宿主：gh 登录态；沙箱：gh 读 GITHUB_TOKEN 占位符，msb 在网络边界替换为真实 token）。
# 只用环境变量设置，只作用于这一次安装，不写任何 gitconfig。
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_0=git+ssh://git@github.com/
export GIT_CONFIG_KEY_1=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_1=ssh://git@github.com/

staging=""
backup=""
install_plugins() {
  mkdir -p "$plugins" "$bun_cache" || return 1
  staging="$(mktemp -d "$(dirname "$plugins")/.plugins-staging.XXXXXX")" || return 1
  install -m 0644 "$manifest" "$staging/package.json" || return 1
  # 保留锁文件和下载缓存，避免每次同步重新解析版本或 clone 私有依赖。
  if [[ -f "$plugins/bun.lock" ]]; then
    cp "$plugins/bun.lock" "$staging/bun.lock" || return 1
  fi
  BUN_INSTALL_CACHE_DIR="$bun_cache" bun install --cwd "$staging" --silent || return 1
  if [[ ! -d "$staging/node_modules" ]]; then
    echo "[-] bun install 未生成 node_modules: $staging" >&2
    return 1
  fi

  backup="$(mktemp -d "$(dirname "$plugins")/.plugins-backup.XXXXXX")" || return 1
  mv "$plugins" "$backup/plugins" || return 1
  if ! mv "$staging" "$plugins"; then
    if ! mv "$backup/plugins" "$plugins"; then
      echo "[-] 原插件恢复失败，备份保留在: $backup/plugins" >&2
    fi
    return 1
  fi
}

if install_plugins; then
  rm -rf "$backup" || true
  exit 0
fi

if [[ -n "$staging" ]]; then rm -rf "$staging" || true; fi
if [[ -n "$backup" && ! -e "$backup/plugins" ]]; then rm -rf "$backup" || true; fi
msg="omp 插件安装或替换失败: $plugins"
if [[ -n "${SB_POSTINSTALL_STRICT:-}" ]]; then
  echo "[-] 错误: $msg" >&2
  exit 1
fi
echo "[!] 警告: $msg" >&2
