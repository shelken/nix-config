{config, ...}: {
  config.shelken.neovim.minimal = true;
  imports = [
    ../core
    ./core.nix

    ../../apps/tailscale
    ../../apps/neovim
  ];
}
