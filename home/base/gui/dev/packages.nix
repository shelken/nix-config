{
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    android-tools
    scrcpy

    television # zed
  ];

  home.shellAliases = {

  };
}
