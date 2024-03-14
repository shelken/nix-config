
alias b := rebuild
alias bd := rebuild-debug

default:
  @just --list

rebuild host:
  @sudo nixos-rebuild switch --upgrade --flake .#{{ host }}

# debug rebuild
rebuild-debug host:
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
  
#
fmt:
  @nix fmt .

# query installed package size
qip:
  # @nix shell nixpkgs#nix-tree nixpkgs#ripgrep
  @nix-store --gc --print-roots | rg -v '/proc/' | rg -Po '(?<= -> ).*' | xargs -o nix-tree

