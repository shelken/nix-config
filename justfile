# set options

set positional-arguments := true
set dotenv-load := true
set dotenv-filename := ".host-profile"

profile := "$PROFILE"
local_secrets_dir := env_var_or_default("LOCAL_SECRETS_DIR", home_dir() + "/code/MyRepo/nix/secrets.nix")

alias b := rebuild
alias bd := rebuild-debug
alias sw := switch
alias hmb := hm-build

# 显式帮助
default:
    @just --list

# git add all
[group('git')]
add:
    @git add .

# 构建前摘要：要真编译什么、要下载多少；kind 为 system（默认）、home、deploy
[group('build')]
plan host=profile kind="system":
    @utils/script/just/nix-plan {{ host }} {{ kind }}

# nixos deploy
[group('build')]
[linux]
deploy host mach:
    @nixos-rebuild switch --flake .#{{ host }} --target-host {{ mach }} --use-remote-sudo --verbose

# 远程部署 darwin 主机: just deploy sakamoto [--dry-activate --verbose ...]
# 默认 --skip-checks: deploy-rs 的 check 阶段会对整个 flake 跑 nix flake check,
# 求值所有主机（含 linux 的 IFD/assertion 问题），与目标节点无关也会失败。
# schema 校验单独跑: nix build .#checks.aarch64-darwin.deploy-schema
[doc('远程部署 darwin 主机，用法: just deploy <主机> [--dry-activate ...]')]
[group('build')]
[macos]
deploy host *args:
    @deploy --skip-checks .#{{ host }} {{ args }}

# 格式化
[group('flake')]
fmt:
    @deadnix -e
    @nix fmt .

# 清理无用的包
[group('gc')]
gc duration="1d":
    @sudo nix profile wipe-history --older-than {{ duration }} --profile /nix/var/nix/profiles/system
    @nix profile wipe-history --older-than {{ duration }} --profile ~/.local/state/nix/profiles/home-manager
    @nix store gc

# 不加 --keep-one 会把 direnv gcroot 一并清掉，devshell 每次进项目都要重新构建
# 清理所有(系统/项目)，每个 direnv 项目保留一个 gcroot
[group('gc')]
gc-all:
    @nh clean all -a --keep-one
    @nix store gc

# 显示历史配置列表
[group('build')]
[macos]
ls-gen:
    @sudo darwin-rebuild --list-generations

# hash 计算统一入口（见 utils/script/just/prefetch --help）
[group('flake')]
prefetch *args:
    @{{ justfile_directory() }}/utils/script/just/prefetch {{ args }}

# 拉取并变基，有本地改动时自动暂存再恢复
[group('git')]
pull:
    @git pull --rebase --autostash

# nixos 重建
[group('build')]
[linux]
rebuild host=profile:
    nh os build -H {{ host }} .

# mac 构建; host 对应当前主机名
[group('build')]
[macos]
rebuild host=profile:
    nh darwin build -H {{ host }} . --extra-experimental-features "nix-command flakes"

# nixos 重建(调试)
[group('build')]
[linux]
rebuild-debug host=profile:
    nh os build -H {{ host }} . -v

# 构建; 调试
[group('build')]
[macos]
rebuild-debug *args:
    nh darwin build -H {{ profile }} . -v -- {{ args }}

# 交互式源码查看
[group('flake')]
[macos]
repl host=profile:
    @nix repl .#darwinConfigurations.{{ host }}

# 交互式源码查看
[group('flake')]
[linux]
repl host=profile:
    @nix repl .#nixosConfigurations.{{ host }}

# 回滚配置
[group('build')]
[macos]
rollback:
    @sudo darwin-rebuild --rollback

# 搜索包
[group('flake')]
search pkg num='10':
    @nh search -l {{ num }} -c nixos-unstable {{ pkg }}

# nixos 重建
[group('build')]
[linux]
switch host=profile:
    @nh os switch -H {{ host }} . --show-activation-logs

# 应用配置; target对应当前主机名
[group('build')]
[macos]
switch *args: rebuild-debug
    nh darwin switch -H {{ profile }} . --show-activation-logs -- {{ args }}

# 仅构建 Home Manager（查看差异，不应用）
[group('build')]
[macos]
hm-build *args:
    nh home build -c {{ profile }} . -v -- {{ args }}

# 仅应用 Home Manager
[group('build')]
[macos]
hm *args:
    nh home switch -c {{ profile }} . --show-activation-logs -- {{ args }}

# 本地联动调试构建：直接挂载本地 secrets.nix，无需等待 push 到 GitHub 和 upp
[group('build')]
[macos]
hm-dev-build *args:
    nh home build -c {{ profile }} . -v -- --override-input secrets path:{{ local_secrets_dir }} {{ args }}

# 本地联动快速应用：直接挂载本地 secrets.nix 应用配置，秒级生效
[group('build')]
[macos]
hm-dev *args:
    nh home switch -c {{ profile }} . -v --show-activation-logs -- --override-input secrets path:{{ local_secrets_dir }} {{ args }}

# 在真实 just hm 运行时逐项打印激活耗时（会应用配置，不改任何 Nix 配置）
[group('build')]
[macos]
hm-timing *args:
    @{{ justfile_directory() }}/utils/script/just/hm-timing "$@"

# 更新整个输入
[group('flake')]
up:
    @nix flake update

# 指定输入更新
[group('flake')]
upp input:
    @nix flake update {{ input }}

# view flake.lock
[group('flake')]
view:
    @nix-melt

# 装机与演练：kexec-cache、Lima 演练机（just anywhere::<配方>）
[group('modules')]
mod anywhere 'just/anywhere.just'

# macOS 专用：brew-diff（just mac::<配方>）
[group('modules')]
[macos]
mod mac 'just/mac.just'

# Linux 专用：gen-image、qip、wipe（just linux::<配方>）
[group('modules')]
[linux]
mod linux 'just/linux.just'

# AI 工具链同步（just ai::mp-sync / just ai::pi-compaction）
[group('modules')]
mod ai 'just/ai.just'

# DNS 配置：编辑加密的 dnsconfig（just dns::edit）
[group('modules')]
mod dns 'just/dns.just'
