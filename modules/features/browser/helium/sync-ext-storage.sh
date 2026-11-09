# shellcheck shell=bash
# 数组 ids 由 home.nix 在本文件前面定义
data=${HELIUM_DATA:-"$HOME/Library/Application Support/net.imput.helium"}
source_profile=Default

# 运行中的 Helium 会改写 LevelDB。SingletonLock 是指向 "<主机名>-<pid>" 的软链
if lock=$(readlink "$data/SingletonLock") && kill -0 "${lock##*-}" 2>/dev/null; then
  echo "Helium 正在运行，请先退出" >&2
  exit 1
fi

shopt -s nullglob
for id in "${ids[@]}"; do
  from="$data/$source_profile/Local Extension Settings/$id"
  if [ ! -d "$from" ]; then
    echo "$id: $source_profile 没有存储，跳过" >&2
    continue
  fi
  for profile in "$data"/Profile\ *; do
    [ -f "$profile/Preferences" ] || continue
    to="$profile/Local Extension Settings/$id"
    mkdir -p "${to%/*}"
    # 先复制到临时目录再替换，中途失败不会留下空存储
    rm -rf "$to.tmp"
    cp -R "$from" "$to.tmp"
    rm -f "$to.tmp/LOCK"
    rm -rf "$to"
    mv "$to.tmp" "$to"
    echo "$id: $source_profile -> ${profile##*/}"
  done
done
