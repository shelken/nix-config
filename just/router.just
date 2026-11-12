# OpenWrt 路由器（nuci）的维护任务，由根 justfile 以 `mod router` 引入：just router::<配方>

# 模块配方默认在本文件所在目录执行，这里统一回到仓库根目录，相对路径才与根 justfile 一致
set working-directory := '..'

target := 'root@router-mine'
# 每次按最新声明重新编译，改完 hosts/router-mine/ 不用单独构建
uci := 'nix build .#router-mine-uci --no-link --print-out-paths'
# 声明里的 {{ op://… }} 经 op inject 展开成明文，只落在临时目录，退出即删；
# 编译产物在 nix store 里只含引用。这里不用 sec-run：它的 service account 读不到 Personal。
# nuci 的 diff 会原样打印路由器上现有的值（删除行也会），所以输出必须经 mask：
# 从未展开的声明里找出写了 {{ op://… }} 的 文件.段.选项，把输出中这些键的值打码
nuci := '''
esc=$'\033'
src=$(''' + uci + ''')
mask_expr=$(jq -r --arg esc "$esc" '[paths(type=="string" and test("\\{\\{ op://")) | .[1:] | join(".") | gsub("\\."; "\\.") | "s/(" + . + "=)[^" + $esc + "]*/\\1<masked>/"] | join(";")' "$src")
mask() { sed -E "$mask_expr"; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
op inject -i "$src" -o "$tmp/uci.json"
mise exec -- nuci '''

[doc('只读：把路由器上某个配置文件的现状转成 nuci 写法并打印，用法: just router::import dhcp')]
import config:
    @modules/features/network/openwrt/uci2nix {{ target }} {{ config }}

[doc('对比声明与路由器现状，显示待变更的差异，不改设备')]
preview:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ nuci }}diff "$tmp/uci.json" --target {{ target }} 2>&1 | mask

[doc('把声明下发到路由器，会改设备；务必先 just router::preview')]
push:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ nuci }}deploy "$tmp/uci.json" --target {{ target }} 2>&1 | mask
