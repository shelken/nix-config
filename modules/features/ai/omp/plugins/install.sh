#!/usr/bin/env bash
# 按清单重建 OMP 插件；安装目录与清单、锁文件、安装后的目录树都一致时直接跳过。宿主激活与沙箱 sb sync 共用本脚本。
# 安装先使用同级暂存目录；替换前备份整个插件目录，替换失败时恢复旧状态。
#
# 用法: install.sh <清单 package.json>
#
# 环境变量:
#   XDG_DATA_HOME          插件目录的取法与 OMP 一致（oh-my-pi packages/utils/src/dirs.ts 的 resolveIf）：
#                          $XDG_DATA_HOME/omp 存在时是 $XDG_DATA_HOME/omp/plugins，否则 ~/.omp/plugins
#   SB_BUN_CACHE_DIR       bun 下载缓存目录，默认 ~/.omp/.bun-cache
#   SB_POSTINSTALL_STRICT  非空：安装失败以非零退出（sb sync）；空：只警告（宿主激活不该因此中断）
#   SB_PLUGINS_FORCE       非空：忽略安装戳，强制重装
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
# 宿主与 guest 都改走 HTTPS，避免触发 SSH 授权。Bun 的 GitHub 下载路径直接读取
# GITHUB_TOKEN；通过 gh 统一读取宿主登录态或沙箱占位符，避免 HTTPS 请求携带 SSH 用户名 git。
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_0=git+ssh://git@github.com/
export GIT_CONFIG_KEY_1=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_1=ssh://git@github.com/

# 安装戳：与插件目录同生同灭（在暂存目录里写好，随整体替换一起换上），所以戳与目录树不会错位。
# 内容 = 已装 package.json 与 bun.lock 的 sha256；戳文件本身的 mtime 是「安装完成」时刻。
stamp_name=".install-stamp"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

stamp_body() {
  printf 'v1 %s %s\n' "$(sha256_of "$1/package.json")" "$(sha256_of "$1/bun.lock")"
}

# 以下任一不成立都按「需要重装」处理（返回非零），不区分原因：
#  - 清单与已装 package.json 逐字节相同（增删插件、改版本都会变）
#  - 已装 package.json / bun.lock 的内容摘要与安装戳一致（锁文件被更新、被替换）
#  - 戳之后目录树里没有任何条目被改过（含 node_modules 被删/被增/被编辑、$plugins 顶层多出文件如 omp-plugins.lock.json）
plugins_current() {
  local stamp="$plugins/$stamp_name"
  [[ -z "${SB_PLUGINS_FORCE:-}" ]] || return 1
  [[ -f "$stamp" && -f "$plugins/package.json" && -f "$plugins/bun.lock" && -d "$plugins/node_modules" ]] || return 1
  cmp -s "$manifest" "$plugins/package.json" || return 1
  [[ "$(stamp_body "$plugins")" == "$(cat "$stamp")" ]] || return 1
  [[ -z "$(find "$plugins" -newer "$stamp" -print -quit)" ]]
}

staging=""
backup=""
install_plugins() {
  local github_token
  mkdir -p "$plugins" "$bun_cache" || return 1
  staging="$(mktemp -d "$(dirname "$plugins")/.plugins-staging.XXXXXX")" || return 1
  install -m 0644 "$manifest" "$staging/package.json" || return 1
  # 保留锁文件和下载缓存，避免每次同步重新解析版本或 clone 私有依赖。
  if [[ -f "$plugins/bun.lock" ]]; then
    cp "$plugins/bun.lock" "$staging/bun.lock" || return 1
  fi
  github_token="$(gh auth token --hostname github.com)" || return 1
  GITHUB_TOKEN="$github_token" BUN_INSTALL_CACHE_DIR="$bun_cache" bun install --cwd "$staging" --silent || return 1
  if [[ ! -d "$staging/node_modules" ]]; then
    echo "[-] bun install 未生成 node_modules: $staging" >&2
    return 1
  fi
  # 戳必须最后写：它的 mtime 要晚于暂存目录里所有文件
  stamp_body "$staging" > "$staging/$stamp_name" || return 1

  backup="$(mktemp -d "$(dirname "$plugins")/.plugins-backup.XXXXXX")" || return 1
  mv "$plugins" "$backup/plugins" || return 1
  if ! mv "$staging" "$plugins"; then
    if ! mv "$backup/plugins" "$plugins"; then
      echo "[-] 原插件恢复失败，备份保留在: $backup/plugins" >&2
    fi
    return 1
  fi
}

if plugins_current; then
  echo "[omp-plugins] 清单、锁文件与已装目录一致，跳过安装: $plugins"
  exit 0
fi

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
