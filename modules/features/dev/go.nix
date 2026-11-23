{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.go ];

  flake.modules.homeManager.go =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      pathExtra = ''export PATH="$PATH:$HOME/go/bin"'';
    in
    {
      config = {
        home.sessionVariables = {
        };

        programs.zsh = {
          envExtra = lib.mkIf config.programs.zsh.enable pathExtra;
          oh-my-zsh.plugins = [ "golang" ];
        };

        programs.bash.bashrcExtra = lib.mkIf config.programs.bash.enable pathExtra;

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
