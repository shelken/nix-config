# set options

set positional-arguments := true
set dotenv-load := true

# from .env

profile := "$PROFILE"
# 本地 secrets store(gopass root); 迁移前可用 LOCAL_SECRETS_DIR 覆盖回旧 clone
local_secrets_dir := env_var_or_default("LOCAL_SECRETS_DIR", home_dir() + "/.local/share/gopass/stores/root")


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
    @ln -s {{ justfile_directory() }}/home/darwin/wm/aerospace/aerospace.toml $HOME/.config/aerospace/aerospace.toml
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

# nixos-anywhere 部署
nixos-anywhere host mach:
    @nixos-anywhere -f .#{{ host }} --target-host {{ mach }} --build-on remote \
    --option substituters https://proxy.ooooo.space/cache.nixos.org \
    --debug \
    --no-substitute-on-destination

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
#   @ln -s {{justfile_directory()}}/home/apps/kitty/kitty.conf $HOME/.config/kitty/kitty.conf

# continue clean
continue-clean:
    @rm -f $HOME/.continue/config.json

# 调试 continue
continue-test: continue-clean
    @ln -s {{ justfile_directory() }}/home/apps/dev/continue/config.json $HOME/.continue/config.json

# 显示历史配置列表
[macos]
ls-gen:
    @sudo darwin-rebuild --list-generations

# 清除nvim
nvim-clean:
    # 变更原因：旧 AstroNvim v3 用户配置在 ~/.config/astronvim/lua/user，当前 v4 配置落在 ~/.config/nvim；两处都清理才符合这个任务名。
    @rm -rf $HOME/.config/astronvim/lua/user $HOME/.config/nvim

# github sha256计算
prefetch-gh owner repo rev="HEAD":
    #!/usr/bin/env bash
    json=$(nix-prefetch-github -- --no-deep-clone --quiet --rev {{ rev }} {{ owner }} {{ repo }})
    owner=$(echo "$json" | jq -r '.owner')
    repo=$(echo "$json" | jq -r '.repo')
    rev=$(echo "$json" | jq -r '.rev' | cut -c 1-8)
    hash=$(echo "$json" | jq -r '.hash')
    cat <<EOF
    pkgs.fetchFromGitHub {
      owner = "$owner";
      repo  = "$repo";
      rev   = "$rev";
      hash  = "$hash";
    };
    EOF

# github
prefetch-gh2 repo rev="HEAD":
    #!/usr/bin/env bash
    function parse_github_url {
      local input={{ repo }}
      local user repo

      if [[ $input == https://github.com/* ]]; then
        user=${input#https://github.com/}
        user=${user%%/*}
        repo=${input#https://github.com/$user/}
      else
        user=${input%%/*}
        repo=${input#*/}
      fi

      echo "$user" "$repo"
    }
    read owner repo <<< $(parse_github_url {{ repo }})
    json=$(nix-prefetch-git -- --no-deepClone --quiet --url "git@github.com:$owner/$repo" --rev {{ rev }})
    rev=$(echo "$json" | jq -r '.rev' | cut -c 1-8)
    hash=$(echo "$json" | jq -r '.hash')
    last_date=$(echo "$json" | jq -r '.date')
    cat <<EOF
    $owner/$repo 上次更新时间：$last_date
    pkgs.fetchFromGitHub {
      owner = "$owner";
      repo  = "$repo";
      rev   = "$rev";
      hash  = "$hash";
    };
    EOF

prefetch-git repo rev:
    @nix-prefetch-git -- --no-deepClone --quiet --url 'git@github.com:{{ repo }}' --rev '{{ rev }}' --fetch-submodules

# nix-prefetch-url, 用于pypi等
prefetch-url url:
    @nix-prefetch-url --print-path '{{ url }}' | awk 'NR>1{print $1}' | xargs nix-hash --flat --base32 --type sha256 --sri

# nix-prefetch-url2, 用于github
prefetch-url2 url:
    @nix-prefetch-url --print-path --unpack '{{ url }}' | awk 'NR>1{print $1}' | xargs nix-hash --type sha256 --sri

prefetch-sha256 url:
    @curl -sL '{{ url }}' | sha256sum

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

# 编辑 sops 密文并提交同步; gitfs 的 sync 不提交非 .age 文件的变更, 故编辑后在此显式提交
[macos]
secret-edit *args:
    #!/usr/bin/env zsh
    cd {{ local_secrets_dir }}
    sops ${*:-sops/secrets/shelken/default.yaml}
    git add -A
    git commit -m "sec: update secrets" || true
    gopass sync

# 体检 secrets store(只读): recipients 一致性 / 未提交内容 / remote 配置
[macos]
secrets-doctor:
    #!/usr/bin/env zsh
    store="{{ local_secrets_dir }}"
    if [[ ! -d "$store/.git" ]]; then
      echo "❌ store 不存在或未初始化: $store"
      exit 1
    fi
    tmp=$(mktemp -d)
    grep -o 'age1[a-z0-9]*' "$store/.age-recipients" 2>/dev/null | sort -u > "$tmp/age"
    if [[ -f "$store/.sops.yaml" ]]; then
      grep -o 'age1[a-z0-9]*' "$store/.sops.yaml" | sort -u > "$tmp/sops"
      if diff -q "$tmp/age" "$tmp/sops" >/dev/null; then
        echo "✅ recipients 一致 ($(wc -l < "$tmp/age" | tr -d ' ') 台机器)"
      else
        echo "⚠️ .age-recipients 与 .sops.yaml 公钥不一致:"
        diff "$tmp/age" "$tmp/sops" || true
      fi
    else
      echo "⏳ .sops.yaml 尚未迁入 store(迁移步骤未完成)"
    fi
    if [[ -n $(git -C "$store" status --porcelain) ]]; then
      echo "⚠️ store 有未提交内容:"
      git -C "$store" status --porcelain
    else
      echo "✅ store 工作区干净"
    fi
    if git -C "$store" remote get-url origin &>/dev/null; then
      echo "✅ remote: $(git -C "$store" remote get-url origin)"
    else
      echo "⏳ store 未配置 remote(迁移步骤未完成)"
    fi
    rm -rf "$tmp"

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
    @ln -s {{ justfile_directory() }}/home/apps/wezterm/wezterm.lua $HOME/.config/wezterm/wezterm.lua

# 清除历史；默认`3d`; 三天前
[linux]
wipe duration="3d":
    @sudo nix profile wipe-history --older-than {{ duration }} --profile /nix/var/nix/profiles/system
