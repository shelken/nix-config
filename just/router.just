# OpenWrt 路由器（nuci）的维护任务，由根 justfile 以 `mod router` 引入：just router::<配方>

# 模块配方默认在本文件所在目录执行，这里统一回到仓库根目录，相对路径才与根 justfile 一致
set working-directory := '..'

target := 'root@router-mine'
# 每次按最新声明重新编译，改完 hosts/router-mine/ 不用单独构建
uci := 'nix build .#router-mine-uci --no-link --print-out-paths'

[doc('只读：把路由器上某个配置文件的现状转成 nuci 写法并打印，用法: just router::import dhcp')]
import config:
    @modules/features/network/openwrt/uci2nix {{ target }} {{ config }}

[doc('对比声明与路由器现状，显示待变更的差异，不改设备')]
preview:
    @mise exec -- nuci diff "$({{ uci }})" --target {{ target }}

[doc('把声明下发到路由器，会改设备；务必先 just router::preview')]
push:
    @mise exec -- nuci deploy "$({{ uci }})" --target {{ target }}
