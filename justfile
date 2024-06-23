# set options
set positional-arguments := true
set dotenv-load := true

# from .env
profile := "$PROFILE"

alias b := rebuild
alias bd := rebuild-debug
alias sw := switch

# 显式帮助
default:
  @just --list

# git add all
add:
  @git add .

# 检查theme
check-themes:
  #!/usr/bin/env bash
  array=("btop" "bat" "squirrel" "lazygit" "wezterm" "yazi" "tmux")
  for i in "${array[@]}"; do
    # echo $(gh repo view catppuccin/"$i" --json name,updatedAt)
    nix-prefetch-git --no-deepClone --quiet --url "git@github.com:catppuccin/$i" --rev HEAD | jq ". | {url, date}" &
  done
  wait

# nixos deploy
[linux]
deploy host mach:
  @nixos-rebuild switch --flake .#{{ host }} --target-host {{ mach }} --use-remote-sudo --verbose

# 格式化
fmt:
  @deadnix -e
  @nix fmt .

# 清理无用的包
gc duration="7d" *args="":
  @nix-collect-garbage --delete-older-than {{ duration }} {{args}}
  @sudo nix-collect-garbage --delete-older-than {{ duration }} {{args}}

# 暂存未提交文件合并
git-temp:
  @git stash save 'temp'
  @git pull --rebase
  @git stash pop

# kitty clean
kitty-clean:
  @rm -f $HOME/.config/kitty/kitty.conf

# 调试 kitty
kitty-test: kitty-clean
  @ln -s {{justfile_directory()}}/home/apps/kitty/kitty.conf $HOME/.config/kitty/kitty.conf

# 显示历史配置列表
[macos]
ls-gen:
  @darwin-rebuild --list-generations

# 清除nvim
nvim-clean:
  @rm -rf $HOME/.config/astronvim/lua/user

# github sha256计算
prefetch-gh owner repo rev="HEAD":
    #!/usr/bin/env bash
    json=$(nix-prefetch-github --no-deep-clone --quiet --rev {{ rev }} {{ owner }} {{ repo }})
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
    local input=$1
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
  just prefetch-gh $owner $repo {{ rev }}

prefetch-git repo rev:
  @nix-prefetch-git --no-deepClone --quiet --url 'git@github.com:{{ repo }}' --rev '{{ rev }}' --fetch-submodules

# nix-prefetch-url, 用于pypi等
prefetch-url url:
  @nix-prefetch-url --print-path '{{ url }}' | awk 'NR>1{print $1}' | xargs nix-hash --flat --base32 --type sha256 --sri

# nix-prefetch-url2, 用于github
prefetch-url2 url:
  @nix-prefetch-url --print-path --unpack '{{ url }}' | awk 'NR>1{print $1}' | xargs nix-hash --type sha256 --sri

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
  @sudo nixos-rebuild switch --upgrade --flake .#{{ host }}

# mac 构建; target对应当前主机名
[macos]
rebuild target=profile: set-proxy
  #!/usr/bin/env bash
  config_target=".#darwinConfigurations.{{target}}.system"
  nix build $config_target --extra-experimental-features "nix-command flakes" 

# nixos 重建(调试)
[linux]
rebuild-debug host=profile:
  @sudo nixos-rebuild switch --upgrade --flake .#{{ host }} --show-trace -L -v

# 构建; 调试
[macos]
rebuild-debug target=profile: set-proxy
  #!/usr/bin/env bash
  config_target=".#darwinConfigurations.{{target}}.system"
  nix build $config_target --extra-experimental-features "nix-command flakes" --show-trace 

# 交互式源码查看
repl:
  @nix repl -f flake:nixpkgs

# 回滚配置
[macos]
rollback:
  @darwin-rebuild --rollback

# mac更新前调整nix到代理
[macos]
set-proxy:
  @sudo python3 utils/script/darwin_set_proxy.py

# nixos 重建
[linux]
switch host=profile: 
  @just rebuild $1

# 应用配置; target对应当前主机名
[macos]
switch target=profile: set-proxy
  #!/usr/bin/env bash
  config_target=".#{{target}}"
  darwin-rebuild switch --flake $config_target

# 更新整个输入
up:
  @nix flake update

# 指定输入更新
upp input:
  @nix flake lock --update-input {{ input }}

# view flake.lock
view:
  @nix-melt

# 调试wez
wez-test:
  @rm -f $HOME/.config/wezterm/wezterm.lua
  @ln -s {{justfile_directory()}}/home/apps/wezterm/wezterm.lua $HOME/.config/wezterm/wezterm.lua

# 清除历史；默认`3d`; 三天前
[linux]
wipe duration="3d":
  @sudo nix profile wipe-history --older-than {{ duration }} --profile /nix/var/nix/profiles/system
