{ pkgs, config, ... }:
let
  shellInit = ''
    # for extension pi-powerline-footer
    export POWERLINE_NERD_FONTS=1
  '';
in
{
  home.packages = with pkgs; [
    rtk
  ];
  shelken.backup.app.pi = [
    "${config.home.homeDirectory}/.pi"
  ];
  programs.zsh.initContent = shellInit;
}
