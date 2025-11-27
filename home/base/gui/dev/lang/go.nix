{
  pkgs,
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.shelken.dev.ide.enable {
    home.sessionVariables = {
      # for go
      GOPROXY = "https://goproxy.io";
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
