
alias b := rebuild

rebuild host:
  @sudo nixos-rebuild switch --upgrade --flake .#{{ host }}
