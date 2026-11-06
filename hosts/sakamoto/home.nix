{ ... }:
{
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  imports = [ ./apps ];
  shelken = { };
}
