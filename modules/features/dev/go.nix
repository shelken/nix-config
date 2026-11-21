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
        };

        home.sessionPath = [ "$HOME/go/bin" ];

        programs.zsh.oh-my-zsh.plugins = [ "golang" ];

        home.packages = with pkgs; [
          go
        ];

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
