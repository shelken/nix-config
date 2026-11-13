{ ... }:
{
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    neovim.minimal = true;
    dev.ai.sandbox.enable = true;
  };
}
