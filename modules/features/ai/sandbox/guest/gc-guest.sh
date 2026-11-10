#!/usr/bin/env bash
# sb gc：mise prune 闲置版本 + bun 缓存旧条目；git 依赖 clone 缓存无条件保留（见 omp/plugins/install.sh）
set -euo pipefail
export SSL_CERT_FILE="$GIT_SSL_CAINFO" CURL_CA_BUNDLE="$GIT_SSL_CAINFO"

mise prune --yes || mise prune --yes   # 宿主 .DS_Store 会让删除报 Directory not empty，重试一次

bun_cache="$SB_MISE_CACHE_DIR/bun-cache"
bun_lock="$XDG_DATA_HOME/omp/plugins/bun.lock"
[[ -f "$bun_lock" ]] || exit 0          # 插件从未安装，无从判断引用，不清空
lock_text=$(cat "$bun_lock")
while IFS= read -r entry; do
  key="${entry#"$bun_cache"/}"; key="${key%@@@1}"
  [[ "$lock_text" == *"\"$key\""* ]] && continue   # 仍被 bun.lock 引用
  rm -rf -- "$entry" || rm -rf -- "$entry"
done < <(find "$bun_cache" -mindepth 1 -maxdepth 2 -type d -name '*@@@1' ! -name '@G@*' ! -name '@GH@*' | sort)
