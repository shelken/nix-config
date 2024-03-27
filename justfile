# set options
set positional-arguments := true
set dotenv-load := true

# from .env
profile := "$PROFILE"

alias b := rebuild
alias bd := rebuild-debug

# 显式帮助
default:
  @just --list

# 格式化
fmt:
  @nix fmt .

# 交互式源码查看
repl:
  @nix repl -f flake:nixpkgs

# 清理无用的包
gc:
  @nix-collect-garbage -d

# 指定输入更新
upp input:
  @nix flake lock --update-input {{ input }}

# 更新整个输入
up:
  @nix flake update

# git add all
add:
  @git add .

# git pull
pull:
  @git pull --rebase

# 查看包文件树
[linux]
qip:
  # @nix shell nixpkgs#nix-tree nixpkgs#ripgrep
  @nix-store --gc --print-roots | rg -v '/proc/' | rg -Po '(?<= -> ).*' | xargs -o nix-tree

# 暂存未提交文件合并
git-temp:
  @git stash save 'temp'
  @git pull --rebase
  @git stash pop

# nix-prefetch-url
prefetch-url url:
  @nix-prefetch-url --print-path --type sha256 '{{ url }}' | xargs nix hash to-sri --type sha256

prefetch-gh owner-repo rev:
  @nix-prefetch-url --print-path --unpack https://github.com/{{ owner-repo }}/archive/{{ rev }}.tar.gz | awk 'NR>1{print $1}' | xargs nix-hash --sri --type sha256

# nix-prefetch-git
prefetch-git repo rev:
  @nix-prefetch-git --url 'git@github.com:{{ repo }}' --rev '{{ rev }}' --fetch-submodules

# nixos 重建
[linux]
rebuild host=profile:
  @sudo nixos-rebuild switch --upgrade --flake .#{{ host }}

# nixos 重建
[linux]
switch host=profile: 
  just rebuild $1

# nixos 重建(调试)
[linux]
rebuild-debug host=profile:
  @sudo nixos-rebuild switch --upgrade --flake .#{{ host }} --show-trace -L -v

# 清除历史；默认`3d`; 三天前
[linux]
wipe duration="3d":
  @sudo nix profile wipe-history --older-than {{ duration }} --profile /nix/var/nix/profiles/system

# mac更新前调整nix到代理
[macos]
set-proxy:
  @sudo python3 utils/script/darwin_set_proxy.py

# mac 构建; target对应当前主机名
[macos]
rebuild target=profile: set-proxy
  #!/usr/bin/env bash
  config_target=".#darwinConfigurations.{{target}}.system"
  nix build $config_target --extra-experimental-features "nix-command flakes" 

# mac 构建; 调试
[macos]
rebuild-debug target=profile: set-proxy
  #!/usr/bin/env bash
  config_target=".#darwinConfigurations.{{target}}.system"
  nix build $config_target --extra-experimental-features "nix-command flakes" --show-trace 

# mac 应用配置; target对应当前主机名
[macos]
switch target=profile: set-proxy
  #!/usr/bin/env bash
  config_target=".#{{target}}"
  ./result/sw/bin/darwin-rebuild switch --flake $config_target
