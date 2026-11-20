#!/usr/bin/env bash
#   XDG_DATA_HOME          插件目录的取法与 OMP 一致（oh-my-pi packages/utils/src/dirs.ts 的 resolveIf）：
#                          $XDG_DATA_HOME/omp 存在时是 $XDG_DATA_HOME/omp/plugins，否则 ~/.omp/plugins
set -euo pipefail

manifest="${1:?用法: install.sh <清单 package.json>}"

if [[ -n "${XDG_DATA_HOME:-}" && -d "$XDG_DATA_HOME/omp" ]]; then
  plugins="$XDG_DATA_HOME/omp/plugins"
else
  plugins="$HOME/.omp/plugins"
fi
bun_cache="${SB_BUN_CACHE_DIR:-$HOME/.omp/.bun-cache}"

# 清单里的私有依赖写成 git+ssh://git@github.com/…，bun 取包时把它解析成 ssh://git@github.com/…，
# 两种前缀都要改写，只改前一种会在 guest 里以 Permission denied (publickey) 失败。
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_0=git+ssh://git@github.com/
export GIT_CONFIG_KEY_1=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_1=ssh://git@github.com/

stamp_name=".install-stamp"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

stamp_body() {
  printf 'v1 %s %s\n' "$(sha256_of "$1/package.json")" "$(sha256_of "$1/bun.lock")"
}

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
  if [[ -f "$plugins/bun.lock" ]]; then
    cp "$plugins/bun.lock" "$staging/bun.lock" || return 1
  fi
  github_token="$(gh auth token --hostname github.com)" || return 1
  GITHUB_TOKEN="$github_token" BUN_INSTALL_CACHE_DIR="$bun_cache" bun install --cwd "$staging" --silent || return 1
  if [[ ! -d "$staging/node_modules" ]]; then
    echo "[-] bun install 未生成 node_modules: $staging" >&2
    return 1
  fi
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
