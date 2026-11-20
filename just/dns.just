set working-directory := '..'

config := 'modules/features/network/dnscontrol/dnsconfig.sops.js'
creds := 'modules/features/network/dnscontrol/creds.json'

# sops 在文件没改动时退出码为 200，不算失败
[doc('编辑加密的 dnsconfig，保存时自动重新加密；改完用 just dns::preview 查看差异')]
edit:
    @sops {{ config }} || test $? -eq 200

[doc('对比线上记录与配置，显示待变更的差异（末尾 Done. 0 corrections. 即已同步）')]
preview: (_run 'preview')

[doc('把差异推到线上 DNS，会改线上记录；务必先 just dns::preview')]
push: (_run 'push')

[private]
_run sub:
    sops exec-file --filename dnsconfig.js {{ config }} \
        "dnscontrol-cf {{ sub }} --config {} --creds {{ creds }}"
