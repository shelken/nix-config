{...}: {
  imports = [
    ../../base/core
    ../../apps/yazi
    ../../apps/tmux
    ../../apps/zsh
    ../../apps/btop.nix
    # ../../base/core/git.nix
    ../../apps/neovim
    ./core.nix
    #./git.nix
    #./starship.nix
  ];
}
