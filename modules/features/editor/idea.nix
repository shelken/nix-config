# IntelliJ IDEA：cask 与命令行包装（idea <path>），只在 workstation
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.idea ];

  flake.modules.darwin.idea.homebrew.casks = [ "intellij-idea" ];

  flake.modules.homeManager.idea =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellScriptBin "idea" ''
          idea_function() {
            local path="$1"
            if [ -z "$path" ]; then
              path="."
            fi
            open -a '/Applications/IntelliJ IDEA.app/Contents/MacOS/idea' "$path"
          }
          idea_function "$@"
        '')
      ];
    };
}
