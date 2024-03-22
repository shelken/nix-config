{...}: {
  imports = [
    #./nushell
    #./tmux
    #./zellij

    #./bash.nix
    #./bat.nix
    ../../apps/yazi
    ../../apps/tmux
    ../../apps/zsh
    ../../apps/btop.nix
    ../../base/core/git.nix
    ../../apps/neovim
    ./core.nix
    #./git.nix
    #./starship.nix
  ];
}
