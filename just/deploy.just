# 远程部署与部署状态；调用 just deploy::<配方>

set working-directory := '..'
set positional-arguments := true

# 默认 --skip-checks：deploy-rs 的 check 阶段会对整个 flake 跑 nix flake check，
# 求值所有主机（含 linux 的 IFD/assertion 问题），与目标节点无关也会失败。
# schema 校验单独跑：nix build .#checks.aarch64-darwin.deploy-schema
[doc('远程部署，用法: just deploy::run <主机> [--dry-activate ...]')]
[macos]
run host *args:
    @deploy --skip-checks .#{{ host }} {{ args }}

[doc('nixos-rebuild 远程部署，用法: just deploy::run <主机> <ssh 目标>')]
[linux]
run host mach:
    @nixos-rebuild switch --flake .#{{ host }} --target-host {{ mach }} --use-remote-sudo --verbose

[doc('并发探测各主机是否落后于当前工作区（只读），用法: just deploy::status [主机...]')]
status *hosts:
    @{{ justfile_directory() }}/utils/script/just/deploy_status.py "$@"
