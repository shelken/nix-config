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

aerospace-clean:
    @rm -f $HOME/.config/aerospace/aerospace.toml

aerospace-test:
    just aerospace-clean
    @ln -s {{ justfile_directory() }}/modules/features/wm/aerospace/aerospace.toml $HOME/.config/aerospace/aerospace.toml
    @aerospace reload-config

# git add all
add:
    @git add .

# 列出不在 nix 管理内的 brew 包（只列出，不删除）
[macos]
brew-diff:
    @brew bundle cleanup --file=$(nix path-info /run/current-system --recursive 2>/dev/null | grep Brewfile | head -1)

# 查看本次构建哪些需要编译、哪些直接下载
[macos]
build-dry host=profile:
    @nix build ".#darwinConfigurations.{{ host }}.system" --dry-run

# nixos deploy
[linux]
deploy host mach:
    @nixos-rebuild switch --flake .#{{ host }} --target-host {{ mach }} --use-remote-sudo --verbose

# 远程部署 darwin 主机: just deploy sakamoto [--dry-activate --verbose ...]
# 默认 --skip-checks: deploy-rs 的 check 阶段会对整个 flake 跑 nix flake check,
# 求值所有主机（含 linux 的 IFD/assertion 问题），与目标节点无关也会失败。
# schema 校验单独跑: nix build .#checks.aarch64-darwin.deploy-schema
[macos]
deploy host *args:
    @deploy --skip-checks .#{{ host }} {{ args }}

# Lima 演练机：按 hosts/vm/lima-test/nixos-anywhere-test.yaml 起一台 Ubuntu 当「待接管的 Linux」
[macos]
lima-target-up name="nixos-anywhere-test":
    limactl start --name={{ name }} --tty=false hosts/vm/lima-test/nixos-anywhere-test.yaml
    @echo "目标 IP: $(just lima-target-ip {{ name }})"

# 演练机在 vzNAT 网卡（lima0）上的 IP，Mac 可直连
[macos]
lima-target-ip name="nixos-anywhere-test":
    @limactl shell {{ name }} ip -4 -o addr show dev lima0 | awk '{print $4}' | cut -d/ -f1

# 删掉演练机，从头再来
[macos]
lima-target-rm name="nixos-anywhere-test":
    limactl delete --force {{ name }}

# qemu 软件模拟，较慢；qemu 由 nix 临时提供，不装进系统
# x86_64 BIOS 演练机：按 hosts/vm/vps-test/nixos-anywhere-vps.yaml 起一台对齐 VPS 规格的 Ubuntu
[macos]
lima-vps-up name="nixos-anywhere-vps":
    nix shell nixpkgs#qemu -c limactl start --name={{ name }} --tty=false hosts/vm/vps-test/nixos-anywhere-vps.yaml
    @echo "SSH 端口: $(just lima-vps-port {{ name }})"

# 演练机映射到 Mac 本机的 SSH 端口（qemu 用户态网络，没有可直连的 IP）
[macos]
lima-vps-port name="nixos-anywhere-vps":
    @limactl list {{ name }} --format '{{ "{{.SSHLocalPort}}" }}'

# 默认在本机构建（x86_64 经 linux-builder），目标机内存小时不必在安装环境里求值
# --extra-files <目录> 把目录里的文件按相同路径放进新系统（sops 的 age 私钥、tailscale 状态都靠它）
# 接管：just nixos-anywhere <主机> <root@地址> [额外参数]，例如 --phases kexec、-i <密钥>、--ssh-port <端口>
nixos-anywhere host target *args:
    @nixos-anywhere -f .#{{ host }} --target-host {{ target }} --build-on local {{ args }}

kexec-cache arch="aarch64" release="":
  #!/usr/bin/env bash
  set -euo pipefail
  arch="{{ arch }}"
  release="{{ release }}"
  if [[ -z "$release" ]]; then
      pkg=$(nix build --no-link --print-out-paths --inputs-from . nixpkgs#nixos-anywhere)
      tmpl=$(grep -rhoa 'https://github.com/nix-community/nixos-images/releases/download/[^"]*' "$pkg" | sort -u | head -1 || true)
      [[ -n "$tmpl" ]] || { echo "在 $pkg 里没找到默认 kexec 地址，请手动指定 release" >&2; exit 1; }
      release=$(sed -E 's#.*/releases/download/([^/]+)/.*#\1#' <<<"$tmpl")
  fi
  url="https://github.com/nix-community/nixos-images/releases/download/${release}/nixos-kexec-installer-noninteractive-${arch}-linux.tar.gz"
  dir="${XDG_CACHE_HOME:-$HOME/.cache}/nixos-anywhere"
  file="$dir/${release}-${arch}-linux.tar.gz"
  mkdir -p "$dir"
  if [[ ! -s "$file" ]]; then
      echo "下载 $url" >&2
      curl -fL --retry 3 -o "$file.part" "$url"
      mv "$file.part" "$file"
  fi
  if [[ ! -s "$file.version" ]]; then
      { tar -tzf "$file" 2>/dev/null || true; } | grep -m1 -oE 'nixos-system-[^/]+' > "$file.version" || true
  fi
  echo "release: $release  安装环境: $(cat "$file.version")" >&2
  echo "$file"

# 格式化
fmt:
    @deadnix -e
    @nix fmt .

# 清理无用的包
gc duration="1d":
    # @nix run nixpkgs#nh -- clean all -a -K {{ duration }}
    # @nh clean all -a -K {{ duration }}
    @sudo nix profile wipe-history --older-than {{ duration }} --profile /nix/var/nix/profiles/system
    @nix profile wipe-history --older-than {{ duration }} --profile ~/.local/state/nix/profiles/home-manager
    @nix store gc

# 清理所有
# @nix-collect-garbage -d
# @sudo nix-collect-garbage -d

# 清理所有(系统/项目)
gc-all:
    # @nix run nixpkgs#nh -- clean all -a
    @nh clean all -a
    @nix store gc

# 生成镜像
[linux]
gen-image host format:
    #!/usr/bin/env bash
    set -e
    nom build .#nixosConfigurations.{{ host }}.config.formats.{{ format }}
    d=$(readlink -f result)
    suffix="${d##*.}"
    ls -hl $d
    rsync -avPL --checksum result pve:/var/lib/vz/template/iso/{{ host }}-latest.$suffix

# 暂存未提交文件合并
git-temp:
    @git stash save 'temp'
    @git pull --rebase
    @git stash pop

# kitty clean
kitty-clean:
    @rm -f $HOME/.config/kitty/kitty.conf

# 调试 kitty
# kitty-test: kitty-clean
#   @ln -s {{justfile_directory()}}/modules/features/terminal/kitty/kitty.conf $HOME/.config/kitty/kitty.conf

# 显示历史配置列表
[macos]
ls-gen:
    @sudo darwin-rebuild --list-generations

# 清除nvim
nvim-clean:
    # 变更原因：旧 AstroNvim v3 用户配置在 ~/.config/astronvim/lua/user，当前 v4 配置落在 ~/.config/nvim；两处都清理才符合这个任务名。
    @rm -rf $HOME/.config/astronvim/lua/user $HOME/.config/nvim

# hash 计算统一入口（见 utils/script/prefetch --help）
prefetch *args:
    @{{ justfile_directory() }}/utils/script/prefetch {{ args }}

# git pull
pull:
    @git pull --rebase

# 查看包文件树
[linux]
qip:
    # @nix shell nixpkgs#nix-tree nixpkgs#ripgrep
    @nix-store --gc --print-roots | rg -v '/proc/' | rg -Po '(?<= -> ).*' | xargs -o nix-tree

# nixos 重建
[linux]
rebuild host=profile:
    # @nix build ".#nixosConfigurations.{{ host }}"
    # @nix run nixpkgs#nh -- os build -H {{ host }} .
    nh os build -H {{ host }} .

# mac 构建; host 对应当前主机名
[macos]
rebuild host=profile:
    # @nix build ".#darwinConfigurations.{{ host }}.system" --extra-experimental-features "nix-command flakes"
    #@nix run nixpkgs#nh -- darwin build -H {{ host }} . -- --extra-experimental-features "nix-command flakes"
    nh darwin build -H {{ host }} . --extra-experimental-features "nix-command flakes"

# nixos 重建(调试)
[linux]
rebuild-debug host=profile:
    # nom build ".#nixosConfigurations.{{ host }}.config.system.build.toplevel" --show-trace --verbose
    # nix run nixpkgs#nh -- os build -H {{ host }} . -v
    nh os build -H {{ host }} . -v

# 构建; 调试
[macos]
rebuild-debug *args:
    # nom build ".#darwinConfigurations.{{ profile }}.system" --extra-experimental-features "nix-command flakes" --show-trace --verbose
    # nix run nixpkgs#nh -- darwin build -H {{ profile }} . -v -- {{ args }}
    nh darwin build -H {{ profile }} . -v -- {{ args }}

# 交互式源码查看
repl host=profile:
    @nix repl .#darwinConfigurations.{{ host }}

# 回滚配置
[macos]
rollback:
    @sudo darwin-rebuild --rollback

# 搜索包
search pkg num='10':
    # @nix run nixpkgs#nh -- search -l {{ num }} -c nixos-unstable {{ pkg }}
    @nh search -l {{ num }} -c nixos-unstable {{ pkg }}

# mac更新前调整nix到代理
[macos]
set-proxy:
    @sudo python3 utils/script/darwin_set_proxy.py

# nixos 重建
[linux]
switch host=profile:
    # nixos-rebuild switch --sudo --flake $".#{{ host }}" --show-trace --verbose
    # @nix run nixpkgs#nh -- os switch -H {{ host }} .
    @nh os switch -H {{ host }} . --show-activation-logs

# 应用配置; target对应当前主机名
[macos]
switch *args: rebuild-debug
    # sudo -E ./result/sw/bin/darwin-rebuild switch --flake ".#{{ profile }}" --show-trace --verbose
    # nix run nixpkgs#nh -- darwin switch -H {{ profile }} . -v -- {{ args }}
    nh darwin switch -H {{ profile }} . -v --show-activation-logs -- {{ args }}

# 仅构建 Home Manager（查看差异，不应用）
[macos]
hm-build *args:
    nh home build -c {{ profile }} . -v -- {{ args }}

# 仅应用 Home Manager
[macos]
hm *args:
    # nix run nixpkgs#nh -- home switch -c {{ profile }} . -v -- {{ args }}
    nh home switch -c {{ profile }} . -v --show-activation-logs -- {{ args }}

# 本地联动调试构建：直接挂载本地 secrets.nix，无需等待 push 到 GitHub 和 upp
[macos]
hm-dev-build *args:
    nh home build -c {{ profile }} . -v -- --override-input secrets path:{{ local_secrets_dir }} {{ args }}

# 本地联动快速应用：直接挂载本地 secrets.nix 应用配置，秒级生效
[macos]
hm-dev *args:
    nh home switch -c {{ profile }} . -v --show-activation-logs -- --override-input secrets path:{{ local_secrets_dir }} {{ args }}

# 在真实 just hm 运行时逐项打印激活耗时（会应用配置，不改任何 Nix 配置）
[macos]
hm-timing *args:
    #!/usr/bin/env bash
    set -euo pipefail
    trace="$(mktemp)"
    hook="$(mktemp)"
    trap 'rm -f "$trace" "$hook"' EXIT
    cat > "$hook" <<'BASH'
    case "$0" in */activate)
      unset BASH_ENV
      trap 'case "$BASH_COMMAND" in
        "_iNote \"Activating %s\" "*) printf "HM_TIMING %s %s\n" "$EPOCHREALTIME" "${BASH_COMMAND##* }" >&2 ;;
        # shortcut: 末项结束依赖当前 HM 的 GC-root 尾声，升级 HM 后需核对。
        run\ --silence\ nix-store\ --realise*currentGenGcPath*) printf "HM_TIMING %s END\n" "$EPOCHREALTIME" >&2 ;;
      esac' DEBUG
    esac
    BASH
    status=0
    env BASH_ENV="$hook" just hm {{ args }} 2>&1 | tee "$trace" | awk '$1 != "HM_TIMING" { print; fflush() }' || status=$?
    awk '$1 == "HM_TIMING" { if(p) printf "%8.1f ms  %s\n",($2-p)*1000,n; p=$2; n=$3; gsub(/"/,"",n) }' "$trace" | sort -k1 -rn
    exit "$status"

# 更新整个输入
up:
    @nix flake update

# 指定输入更新
upp input:
    @nix flake update {{ input }}

# view flake.lock
view:
    @nix-melt

# 调试wez
wez-test:
    @rm -f $HOME/.config/wezterm/wezterm.lua
    @ln -s {{ justfile_directory() }}/modules/features/terminal/wezterm/wezterm.lua $HOME/.config/wezterm/wezterm.lua


# 同步 magpie 模型能力差集到 omp models.yml
mp-sync:
    @{{ justfile_directory() }}/modules/features/ai/omp/sync-mp-models.sh
# 清除历史；默认`3d`; 三天前
[linux]
wipe duration="3d":
    @sudo nix profile wipe-history --older-than {{ duration }} --profile /nix/var/nix/profiles/system
