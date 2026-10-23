# Go 工具链：只有主力机需要
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.go ];

  flake.modules.homeManager.go =
    {
      pkgs,
      config,
      ...
    }:
    {
      config = {
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
    };
}
