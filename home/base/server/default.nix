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
    ../../base/code/git.nix
    ../../apps/neovim
    ./core.nix
    #./git.nix
    #./starship.nix
  ];
}
