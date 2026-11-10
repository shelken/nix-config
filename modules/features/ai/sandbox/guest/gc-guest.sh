#!/usr/bin/env bash
# sb gc 在 VM 内执行的脚本；环境（路径、PATH、mise 目录）由 _guest.nix 的包装加载 guest-env.sh。
# 清理不放进 sb sync：删除会破坏补齐「失败可无限重试」的幂等性，sync 只能补缺。
set -euo pipefail

dry="${SB_GC_DRY_RUN:-}"
bun_cache="$SB_MISE_CACHE_DIR/bun-cache"
bun_lock="$XDG_DATA_HOME/omp/plugins/bun.lock"
mise_kb=0
bun_kb=0

# guest 的 HTTPS 出口由 msb 重签证书，只信任镜像里的 msb CA（与 sync-guest.sh 同一原因）
export SSL_CERT_FILE="$GIT_SSL_CAINFO" CURL_CA_BUNDLE="$GIT_SSL_CAINFO"

kb2h() { numfmt --to=iec-i --suffix=B --from-unit=1024 "$1"; }

# dry-run 用独立前缀，验证时靠「不含 [gc] 删除」证明什么都没删
say_delete() { # 路径 大小(KB)
  if [[ -n "$dry" ]]; then
    echo "[gc-dry] 将删除 $1 ($(kb2h "$2"))"
  else
    echo "[gc] 删除 $1 ($(kb2h "$2"))"
  fi
}

echo "[gc] 1. 回收 mise 闲置版本..."
if [[ -n "$dry" ]]; then
  # 不跑 mise prune --dry-run：它的判定依赖 tracked-configs，与真实删除结果不一定一致。
  # 这里只报占用，不判断引用，也不计入可回收合计
  echo "[gc-dry] mise prune 在 dry-run 下不执行，以下为 installs 下各完整版本目录的占用"
  while IFS= read -r d; do
    echo "[gc-dry] prune 候选 $d ($(kb2h "$(du -sk "$d" | cut -f1)"))"
  done < <(find "$SB_MISE_DATA_DIR/installs" -mindepth 2 -maxdepth 2 -type d | sort)
else
  snap=$(mktemp)
  find "$SB_MISE_DATA_DIR/installs" -mindepth 2 -maxdepth 2 -type d -exec du -sk {} + >"$snap"
  # 宿主 Finder/Spotlight 会往共用层写 .DS_Store，目录删到一半时新文件会让删除报 Directory not empty；重试一次即可收尾
  mise prune --yes || mise prune --yes
  while read -r kb d; do
    if [[ ! -d "$d" ]]; then
      say_delete "$d" "$kb"
      mise_kb=$((mise_kb + kb))
    fi
  done <"$snap"
  rm -f "$snap"
fi

echo "[gc] 2. 裁剪 bun 缓存里的旧版本条目..."
if [[ ! -f "$bun_lock" ]]; then
  echo "[gc] 保留 $bun_cache (原因: 没有 $bun_lock，插件从未安装，无从判断引用)"
else
  # 条目形态：<cache>/<pkg>@<ver>@@@1 与 <cache>/@scope/<pkg>@<ver>@@@1 是真实目录，
  # 同级的 <pkg>/<ver>@@@1 是指向它的符号链接，删真实目录时一起删。
  # *.git、@G@*、@GH@* 是 git 依赖的 clone 缓存：无条件保留，清掉会让私有依赖重新 clone（见 omp/plugins/install.sh）
  lock_text=$(cat "$bun_lock")
  while IFS= read -r entry; do
    key="${entry#"$bun_cache"/}"
    key="${key%@@@1}"
    # bun.lock 的 packages 段按 "包名@版本" 逐条记录引用，命中即仍在使用
    if [[ "$lock_text" == *"\"$key\""* ]]; then
      continue
    fi
    kb=$(du -sk "$entry" | cut -f1)
    say_delete "$entry" "$kb"
    bun_kb=$((bun_kb + kb))
    if [[ -n "$dry" ]]; then
      continue
    fi
    # 同上：删到一半被宿主塞进新文件时重试一次
    rm -rf -- "$entry" || rm -rf -- "$entry"
    name="${key##*/}"
    alias="$(dirname "$entry")/${name%@*}/${name##*@}@@@1"
    if [[ -L "$alias" ]]; then
      rm -f -- "$alias"
    fi
  done < <(
    find "$bun_cache" -mindepth 1 -maxdepth 2 -type d -name '*@@@1' \
      ! -name '@G@*' ! -name '@GH@*' | sort
  )
  while IFS= read -r d; do
    echo "[gc] 保留 $d (原因: git 依赖 clone 缓存)"
  done < <(
    find "$bun_cache" -mindepth 1 -maxdepth 1 \
      \( -name '*.git' -o -name '@G@*' -o -name '@GH@*' \) | sort
  )
fi

echo "[gc] 汇总: 回收 $(kb2h "$((mise_kb + bun_kb))")（mise $(kb2h "$mise_kb") + bun 缓存 $(kb2h "$bun_kb")）"
if [[ -n "$dry" ]]; then
  echo "[gc-dry] 以上为预估，加 --yes 执行删除"
fi
