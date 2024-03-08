
alias b := rebuild

default:
  @just --list

rebuild host:
  @sudo nixos-rebuild switch --upgrade --flake .#{{ host }}

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
