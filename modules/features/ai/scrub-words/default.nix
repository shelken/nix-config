{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.scrub-words ];

  flake.modules.homeManager.scrub-words =
    { pkgs, ... }:
    let
      scrub-words = pkgs.writeShellApplication {
        name = "scrub-words";
        runtimeInputs = [
          pkgs.python3
          pkgs.lsof
        ];
        text = ''exec python3 ${./scrub_words.py} "$@"'';
      };
    in
    {
      home.packages = [ scrub-words ];
    };
}
