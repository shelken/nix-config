{ ... }:
{
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    secrets.enable = true;
    wm.aerospace.enable = true;
    neovim.minimal = true;
  };
}
