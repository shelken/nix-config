{pkgs, ...}: let
  jdk = pkgs.jdk17;
in {
  # java
  programs.java = {
    enable = true;
    package = jdk;
  };
  # for my vscode config
  # home.file.".config/lib/jdk17".source = "${jdk.home}";
  xdg.configFile = {
    "lib/jdk17" = {
      source = jdk.home;
    };
  };
}
