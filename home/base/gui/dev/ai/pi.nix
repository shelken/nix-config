{ pkgs, config, ... }:
{
  home.packages = with pkgs; [
    rtk
  ];
  shelken.backup.app.pi = [
    "${config.home.homeDirectory}/.pi"
  ];
}
