{mylib, ...}: {
  imports =
    (mylib.scanPaths ./.)
    ++ [
      ../../apps/yazi
      ../../apps/tmux
    ];
}
