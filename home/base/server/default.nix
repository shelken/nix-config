{...}: {
  imports = [
    #./nushell
    #./tmux
    #./zellij

    #./bash.nix
    #./bat.nix
    ../../apps/yazi.nix
    ../../apps/zsh.nix
    ../../apps/btop.nix
    ../../base/code/git.nix
    ../../apps/neovim
    ./core.nix
    #./git.nix
    #./starship.nix
  ];
}
