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

aerospace-clean:
  @rm -f $HOME/.config/aerospace/aerospace.toml

aerospace-test:
  just aerospace-clean
  @ln -s {{justfile_directory()}}/home/darwin/wm/aerospace/aerospace.toml $HOME/.config/aerospace/aerospace.toml
  @aerospace reload-config

# git add all
add:
  @git add .

# 检查theme
check-themes:
  #!/usr/bin/env bash
  array=("btop" "bat" "squirrel" "lazygit" "wezterm" "yazi" "tmux")
  for i in "${array[@]}"; do
    # echo $(gh repo view catppuccin/"$i" --json name,updatedAt)
    (just prefetch-gh2 catppuccin/$i) &
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
gc duration="7d":
  @nh clean all -K {{duration}}

# 清理所有
# @nix-collect-garbage -d
# @sudo nix-collect-garbage -d
gc-all:
  @nh clean all

# 生成镜像
[linux]
gen-image host format:
  #!/usr/bin/env bash
  nom build .#nixosConfigurations.{{host}}.config.formats.{{format}}
  d=$(readlink -f result)
  suffix="${d##*.}"
  ls -hl $d
  rsync -avPL --checksum result pve:/var/lib/vz/template/iso/{{host}}-latest.$suffix

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

# continue clean
continue-clean:
  @rm -f $HOME/.continue/config.json
# 调试 continue
continue-test: continue-clean
  @ln -s {{justfile_directory()}}/home/apps/dev/continue/config.json $HOME/.continue/config.json

# 显示历史配置列表
[macos]
ls-gen:
  @sudo darwin-rebuild --list-generations

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
  json=$(nix-prefetch-git --no-deepClone --quiet --url "git@github.com:$owner/$repo" --rev {{rev}})
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

# raycast 最新配置导出
[macos]
raycast-export:
  @./utils/script/capture-raycast-config.zsh e ./home/apps/raycast

# raycast 最新配置导入
[macos]
raycast-import:
  @./utils/script/capture-raycast-config.zsh i ./home/apps/raycast

# nixos 重建
[linux]
rebuild host=profile:
  @nh os build -H {{host}} .

# mac 构建; host 对应当前主机名
[macos]
rebuild host=profile: set-proxy
  @nh darwin build -H {{host}} .

# nixos 重建(调试)
[linux]
rebuild-debug host=profile:
  nh os build -H {{host}} . -v

# 构建; 调试
[macos]
rebuild-debug host=profile args="": set-proxy
  nh darwin build -H {{host}} . -v {{args}}

# 交互式源码查看
repl:
  @nix repl -f flake:nixpkgs

# 回滚配置
[macos]
rollback:
  @sudo darwin-rebuild --rollback

# 搜索包
search pkg num='10':
  @nh search -l {{num}} -c nixos-unstable {{pkg}}

# mac更新前调整nix到代理
[macos]
set-proxy:
  @sudo python3 utils/script/darwin_set_proxy.py

# nixos 重建
[linux]
switch host=profile: 
  @nh os switch -a -H {{host}} .

# 应用配置; target对应当前主机名
[macos]
switch host=profile: set-proxy
  @nh darwin switch -a -H {{host}} .

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
  @ln -s {{justfile_directory()}}/home/apps/wezterm/wezterm.lua $HOME/.config/wezterm/wezterm.lua

# 清除历史；默认`3d`; 三天前
[linux]
wipe duration="3d":
  @sudo nix profile wipe-history --older-than {{ duration }} --profile /nix/var/nix/profiles/system
