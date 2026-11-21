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
