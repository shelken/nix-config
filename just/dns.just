# DNS 配置（dnscontrol）的维护任务，由根 justfile 以 `mod dns` 引入：just dns::<配方>

# 模块配方默认在本文件所在目录执行，这里统一回到仓库根目录，相对路径才与根 justfile 一致
set working-directory := '..'

config := 'modules/features/network/dnscontrol/dnsconfig.sops.js'
creds := 'modules/features/network/dnscontrol/creds.json'
# 文件位置由 modules/features/network/dnscontrol/_dnscontrol.nix 的 sops.secrets 决定
token_file := home_directory() / '.config/dnscontrol/cloudflare-api-token'

# sops 在文件没改动时退出码为 200，不算失败
[doc('编辑加密的 dnsconfig，保存时自动重新加密；改完用 just dns::preview 查看差异')]
edit:
    @sops {{ config }} || test $? -eq 200

[doc('对比线上记录与配置，只显示差异（输出为空即已同步）')]
preview: (_run 'preview')

[doc('把差异推到线上 DNS，会改线上记录；务必先 just dns::preview')]
push: (_run 'push')

# 配置由 sops 直接从密文解密，经 FIFO 交给 dnscontrol，明文不落盘，改完无需 just hm
[private]
_run sub:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! token=$(< "{{ token_file }}") || [[ -z $token ]]; then
        echo "读不到 sops 的 dnscontrol/cloudflare-api-token：{{ token_file }}（本机未启用 secrets，或还没激活过）" >&2
        exit 1
    fi
    export CLOUDFLARE_API_TOKEN=$token
    sops exec-file --filename dnsconfig.js {{ config }} \
        "mise exec -- dnscontrol {{ sub }} --config {} --creds {{ creds }}"
