{mylib, ...}: {
  imports =
    (mylib.scanPaths ./.)
    ++ [
      ../../apps/btop.nix
      ../../apps/yazi
      ../../apps/tmux
      ../../apps/zsh
    ];
}
