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

# 列出不在 nix 管理内的 brew 包（只列出，不删除）
[group('tools')]
[macos]
brew-diff:
    @brew bundle cleanup --file=$(nix path-info /run/current-system --recursive 2>/dev/null | grep Brewfile | head -1)

# 构建前摘要：要真编译什么、要下载多少；kind 为 system（默认）、home、deploy
[group('build')]
plan host=profile kind="system":
    @utils/script/nix-plan {{ host }} {{ kind }}

# nixos deploy
[group('build')]
[linux]
deploy host mach:
    @nixos-rebuild switch --flake .#{{ host }} --target-host {{ mach }} --use-remote-sudo --verbose

# 远程部署 darwin 主机: just deploy sakamoto [--dry-activate --verbose ...]
# 默认 --skip-checks: deploy-rs 的 check 阶段会对整个 flake 跑 nix flake check,
# 求值所有主机（含 linux 的 IFD/assertion 问题），与目标节点无关也会失败。
# schema 校验单独跑: nix build .#checks.aarch64-darwin.deploy-schema
[group('build')]
[macos]
deploy host *args:
    @deploy --skip-checks .#{{ host }} {{ args }}

# Lima 演练机：按 hosts/vm/lima-test/nixos-anywhere-test.yaml 起一台 Ubuntu 当「待接管的 Linux」
[group('lima')]
[macos]
lima-target-up name="nixos-anywhere-test":
    limactl start --name={{ name }} --tty=false hosts/vm/lima-test/nixos-anywhere-test.yaml
    @echo "目标 IP: $(just lima-target-ip {{ name }})"

# 演练机在 vzNAT 网卡（lima0）上的 IP，Mac 可直连
[group('lima')]
[macos]
lima-target-ip name="nixos-anywhere-test":
    @limactl shell {{ name }} ip -4 -o addr show dev lima0 | awk '{print $4}' | cut -d/ -f1

# 删掉演练机，从头再来
[group('lima')]
[macos]
lima-target-rm name="nixos-anywhere-test":
    limactl delete --force {{ name }}

# qemu 软件模拟，较慢；qemu 由 nix 临时提供，不装进系统
# x86_64 BIOS 演练机：按 hosts/vm/vps-test/nixos-anywhere-vps.yaml 起一台对齐 VPS 规格的 Ubuntu
[group('lima')]
[macos]
lima-vps-up name="nixos-anywhere-vps":
    nix shell nixpkgs#qemu -c limactl start --name={{ name }} --tty=false --timeout=30m hosts/vm/vps-test/nixos-anywhere-vps.yaml
    @echo "SSH 端口: $(just lima-vps-port {{ name }})"

# 演练机映射到 Mac 本机的 SSH 端口（qemu 用户态网络，没有可直连的 IP）
[group('lima')]
[macos]
lima-vps-port name="nixos-anywhere-vps":
    @limactl list {{ name }} --format '{{ "{{.SSHLocalPort}}" }}'

[group('lima')]
kexec-cache arch="aarch64" release="":
    @{{ justfile_directory() }}/utils/script/just/kexec-cache "$@"

# 格式化
[group('tools')]
fmt:
    @deadnix -e
    @nix fmt .

# 清空 linux-builder VM 的 guest 磁盘，下次启动得到空 Nix store
# 磁盘是稀疏文件，只会涨不会缩；只有在肯重新下载/重编译时才值得重置
[group('tools')]
[macos]
builder-reset:
    @{{ justfile_directory() }}/utils/script/just/builder-reset

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

# 生成镜像（变体由 nixpkgs 提供：iso / iso-installer / qemu / proxmox / sd-card …）
[group('build')]
[linux]
gen-image host format:
    @{{ justfile_directory() }}/utils/script/just/gen-image "$@"

# 暂存未提交文件合并
[group('git')]
git-temp:
    @git stash save 'temp'
    @git pull --rebase
    @git stash pop

# kitty clean
[group('tools')]
kitty-clean:
    @rm -f $HOME/.config/kitty/kitty.conf

# 显示历史配置列表
[group('build')]
[macos]
ls-gen:
    @sudo darwin-rebuild --list-generations

# hash 计算统一入口（见 utils/script/prefetch --help）
[group('flake')]
prefetch *args:
    @{{ justfile_directory() }}/utils/script/prefetch {{ args }}

# git pull
[group('git')]
pull:
    @git pull --rebase

# 查看包文件树
[group('tools')]
[linux]
qip:
    @nix-store --gc --print-roots | rg -v '/proc/' | rg -Po '(?<= -> ).*' | xargs -o nix-tree

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
repl host=profile:
    @nix repl .#darwinConfigurations.{{ host }}

# 回滚配置
[group('build')]
[macos]
rollback:
    @sudo darwin-rebuild --rollback

# 搜索包
[group('flake')]
search pkg num='10':
    @nh search -l {{ num }} -c nixos-unstable {{ pkg }}

# mac更新前调整nix到代理
[group('tools')]
[macos]
set-proxy:
    @sudo python3 utils/script/darwin_set_proxy.py

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

# 调试wez
[group('tools')]
wez-test:
    @rm -f $HOME/.config/wezterm/wezterm.lua
    @ln -s {{ justfile_directory() }}/modules/features/terminal/wezterm/wezterm.lua $HOME/.config/wezterm/wezterm.lua


# 同步 magpie 模型能力差集到 omp models.yml
[group('ai')]
mp-sync:
    @{{ justfile_directory() }}/utils/script/sync-mp-models.sh

# 按模型上下文窗口回填 pi settings.json 的 reserveTokens（节点见脚本开头）
[group('ai')]
pi-compaction:
    @{{ justfile_directory() }}/utils/script/sync_pi_compaction.py

# 清除历史；默认`3d`; 三天前
[group('gc')]
[linux]
wipe duration="3d":
    @sudo nix profile wipe-history --older-than {{ duration }} --profile /nix/var/nix/profiles/system
