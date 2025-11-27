{
  pkgs,
  lib,
  config,
  ...
}:
let
  jdk = pkgs.jdk17;
in
{
  config = lib.mkIf config.shelken.dev.ide.enable {
    # java
    programs.java = {
      enable = true;
      package = jdk;
    };

    home.packages = with pkgs; [
      #-- java
      jdk17
      maven
    ];

    # for my vscode config
    # home.file.".config/lib/jdk1z 7".source = "${jdk.home}";
    xdg.configFile = {
      "lib/jdk17" = {
        source = jdk.home;
      };
    };
  };
}
