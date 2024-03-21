{...}: {
  imports = [
    ../base/core
    ../base/home.nix
    ../apps/neovim
    ./core.nix
    ./shell.nix
  ];
}
