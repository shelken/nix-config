{
  pkgs,
  lib,
  config,
  mylib,
  ...
}:
{
  options.shelken.dev.go = {
    enable = mylib.mkBoolOpt false "Whether or not use.";
  };
  config = lib.mkIf config.shelken.dev.go.enable {
    home.sessionVariables = {
      # for go
      # GOPROXY = "https://goproxy.io";
    };

    home.packages = with pkgs; [
      #-- golang
      go
    ];

    # for go goPath
    programs.go = {
      enable = true;
      env = {
        GOPATH = [
          "${config.home.homeDirectory}/go"
        ];
      };
    };
  };
}
