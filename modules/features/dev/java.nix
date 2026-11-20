# Java 工具链（JDK17 + Maven）：可选功能，想用时主机 imports 一行
{ config, ... }:
{
  flake.modules.homeManager.java =
    {
      pkgs,
      ...
    }:
    let
      jdk = pkgs.jdk17;
    in
    {
      programs.java = {
        enable = true;
        package = jdk;
      };

      home.packages = with pkgs; [
        jdk17
        maven
      ];

      xdg.configFile = {
        "lib/jdk17" = {
          source = jdk.home;
        };
      };
    };
}
