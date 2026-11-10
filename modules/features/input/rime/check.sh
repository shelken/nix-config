#!/usr/bin/env bash
# 在临时目录里用 librime 真实编译一次将要部署的 rime 配置，不碰 ~/Library/Rime，也不启动鼠须管。
# 用法：rime-deploy-check.sh <仓库或工作区根目录> <主机名>
set -euo pipefail

repo=$(cd "$1" && pwd)
host=$2
shared="/Library/Input Methods/Squirrel.app/Contents/SharedSupport"
custom="$repo/modules/features/input/rime/custom"

[ -d "$shared" ] || { echo "FAIL: 找不到鼠须管的共享数据目录 $shared"; exit 1; }
[ -d "$custom" ] || { echo "FAIL: 找不到 $custom"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/user" "$work/tmp"

files=$(nix build "$repo#homeConfigurations.$host.config.home-files" --no-link --print-out-paths)
# liveEdit 主机上 custom 是指向主仓库的软链，分支合并前可能悬空，所以直接取工作区里的文件
for f in "$files/Library/Rime"/*; do
  case "$f" in
    *.custom.yaml) ;;
    *) cp -RL "$f" "$work/user/" ;;
  esac
done
cp "$custom"/*.custom.yaml "$work/user/"
chmod -R u+w "$work/user"

# glog 把日志写到 TMPDIR；nix shell 会改掉 TMPDIR，所以直接调 store 里的二进制
deployer=$(nix build nixpkgs#librime --no-link --print-out-paths)/bin/rime_deployer
TMPDIR="$work/tmp" "$deployer" --build "$work/user" "$shared" "$work/user/build" >/dev/null 2>&1 || {
  echo "FAIL: rime_deployer 退出码非 0"
  exit 1
}

log=$(find "$work/tmp" -name 'rime.tools.*INFO*.log' | head -1)
[ -n "$log" ] || { echo "FAIL: 没有找到部署日志"; exit 1; }

fail=0
summary=$(grep -o 'finished updating schemas: .*' "$log" || true)
echo "schemas: ${summary:-<无>}"
[ "$summary" = "finished updating schemas: 3 success, 0 failure." ] || fail=1

errors=$(grep -c '^E' "$log" || true)
echo "errors: $errors"
[ "$errors" = 0 ] || { grep '^E' "$log" | head -5; fail=1; }

list=$(awk '/^schema_list:/{f=1;next} f&&/^  - /{print $NF;next} f{exit}' "$work/user/build/default.yaml" | tr '\n' ' ')
echo "schema_list: $list"
[ "$list" = "double_pinyin_flypy " ] || fail=1

# nixpkgs 的 librime 不带 lua 插件，缺脚本时上面的编译照样通过，所以单独核对引用到的文件
for mod in $(grep -ohE 'lua_[a-z]+@\*[A-Za-z_]+' "$work/user"/*.schema.yaml | sed 's/.*@\*//' | sort -u); do
  [ -e "$work/user/lua/$mod.lua" ] || { echo "缺少 lua/$mod.lua"; fail=1; }
done
for cfg in $(grep -ohE 'opencc_config: *[A-Za-z0-9_.]+' "$work/user"/*.schema.yaml | awk '{print $2}' | sort -u); do
  [ -e "$work/user/opencc/$cfg" ] || [ -e "$shared/opencc/$cfg" ] || { echo "缺少 opencc/$cfg"; fail=1; }
done

if [ "$fail" = 0 ]; then echo PASS; else echo FAIL; exit 1; fi
