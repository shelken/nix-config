{...}: {
  imports = [
    ../core
    ./core.nix

    ../../apps/tailscale
    ../../apps/neovim
    ../../apps/vscode-server
  ];
}
