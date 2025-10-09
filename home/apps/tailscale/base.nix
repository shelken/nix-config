{ ... }:
let
  shellIntegrationInit = {
    zsh = builtins.readFile ./tailscale.zsh;
  };
in
{
  programs.zsh.initContent = shellIntegrationInit.zsh;
}
