{...}: let
  shellIntegrationInit = {
    zsh = builtins.readFile ./tailscale.zsh;
  };
in {
  programs.zsh.initExtra = shellIntegrationInit.zsh;
}
