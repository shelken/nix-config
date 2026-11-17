# k3s 节点：调用 just k8s::<配方>

set working-directory := '..'
set positional-arguments := true

[doc('逐台部署 k3s 节点，agent 在前、控制面最后，每台健康后再继续；不带参数部署全部')]
deploy *nodes:
    @{{ justfile_directory() }}/utils/script/just/k8s-deploy "$@"
