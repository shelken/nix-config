{mylib, ...}: {
  imports =
    (mylib.scanPaths ./.)
    ++ [
      ../base/core
      ../base/home.nix
      # 特定应用
      ../apps/neovim
      ../apps/zsh
      ../apps/dev
      ../apps/wezterm
      ../apps/squirrel
      ../apps/kitty
      ../apps/zellij
    ];
}
