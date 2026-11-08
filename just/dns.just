# DNS 配置（dnscontrol）的维护任务，由根 justfile 以 `mod dns` 引入：just dns::<配方>

# 模块配方默认在本文件所在目录执行，这里统一回到仓库根目录，相对路径才与根 justfile 一致
set working-directory := '..'

# sops 在文件没改动时退出码为 200，不算失败
[doc('用 $EDITOR 编辑加密的 dnsconfig，保存时自动重新加密；改完再 just hm 并 dnscontrol-ctl preview')]
edit:
    @sops modules/features/network/dnscontrol/dnsconfig.sops.js || test $? -eq 200
