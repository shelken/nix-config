{mylib, ...}: {
  imports =
    (mylib.scanPaths ./.)
    ++ [
      ../base/core
      ../base/home.nix
      ../apps/neovim
      ../apps/zsh
      ../apps/dev
      ../apps/wezterm
    ];
}
