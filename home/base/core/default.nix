{mylib, ...}: {
  imports =
    (mylib.scanPaths ./.)
    ++ [
      ../../apps/btop
      ../../apps/yazi
      # ../../apps/tmux
      ../../apps/zsh
      ../../apps/dev/direnv.nix
      ../../apps/fastfetch
      ../../apps/zellij
    ];
}
