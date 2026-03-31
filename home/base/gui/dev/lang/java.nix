{
  pkgs,
  lib,
  config,
  mylib,
  ...
}:
let
  jdk = pkgs.jdk17;
in
{
  options.shelken.dev.java = {
    enable = mylib.mkBoolOpt false "Whether or not use.";
  };
  config = lib.mkIf config.shelken.dev.java.enable {
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
