# set options
set positional-arguments := true
set dotenv-load := true

# from .env
profile=$PROFILE

alias b := rebuild
alias bd := rebuild-debug

default:
  @just --list

# format
fmt:
  @nix fmt .

# rebuild
rebuild host=profile:
  @sudo nixos-rebuild switch --upgrade --flake .#{{ host }}

# debug rebuild
rebuild-debug host=profile:
  @sudo nixos-rebuild switch --upgrade --flake .#{{ host }} --show-trace -L -v

# clear old-history
wipe duration:
  @sudo nix profile wipe-history --older-than {{ duration }} --profile /nix/var/nix/profiles/system

# nix-collect-garbage
gc:
  @sudo nix-collect-garbage -d

# update a particular flake input
update-input input:
  @sudo nix flake lock --update-input {{ input }}

# update all flake inputs
update:
  @sudo nix flake update

# git add file
add:
  @git add .

# query installed package size
qip:
  # @nix shell nixpkgs#nix-tree nixpkgs#ripgrep
  @nix-store --gc --print-roots | rg -v '/proc/' | rg -Po '(?<= -> ).*' | xargs -o nix-tree

git-temp:
  @git stash save 'temp'
  @git pull --rebase
  @git stash pop

[macos]
set-proxy:
  @sudo python3 utils/script/darwin_set_proxy.py

[macos]
darwin-build target=profile:
  #!/usr/bin/env bash
  config_target=".#darwinConfigurations.{{target}}.system"
  nix build $config_target --extra-experimental-features "nix-command flakes" 

[macos]
darwin-switch target=profile:
  #!/usr/bin/env bash
  config_target=".#{{target}}"
  ./result/sw/bin/darwin-rebuild switch --flake $config_target 
