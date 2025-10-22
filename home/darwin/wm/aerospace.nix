{
  lib,
  mylib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.wm.aerospace;

  scripts = [
    "get-app-bundleid"
    "open-terminal-in-finder-path"
    "pip-move"
  ];

  writeShellBin =
    name: pkgs.writeShellScriptBin "as-${name}" (builtins.readFile ./aerospace/scripts/${name}.sh);

  aerospaceTomlPath = "${config.home.homeDirectory}/nix-config/home/darwin/wm/aerospace/aerospace.toml";
in
{
  options.shelken.wm.aerospace = {
    enable = mkBoolOpt false "Whether or not to enable aerospace.";
  };

  config = mkIf cfg.enable {
    home.packages = map writeShellBin scripts;
    xdg.configFile = {
      "aerospace/aerospace.toml" = {
        source = config.lib.file.mkOutOfStoreSymlink aerospaceTomlPath;
        force = true;
      };
    };
  };
}
