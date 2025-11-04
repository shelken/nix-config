{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.wm.hyprspace;

  # scripts = [
  #   "get-app-bundleid"
  #   "open-terminal-in-finder-path"
  #   "pip-move"
  # ];

  # writeShellBin =
  #   name: pkgs.writeShellScriptBin "as-${name}" (builtins.readFile ./aerospace/scripts/${name}.sh);

  hyprspaceTomlPath = "${config.home.homeDirectory}/nix-config/home/darwin/wm/hyprspace/hyprspace.toml";
in
{
  options.shelken.wm.hyprspace = {
    enable = mkBoolOpt false "Whether or not to enable hyprspace.";
  };

  config = mkIf cfg.enable {
    # home.packages = map writeShellBin scripts;
    xdg.configFile = {
      "hyprspace/hyprspace.toml" = {
        source = config.lib.file.mkOutOfStoreSymlink hyprspaceTomlPath;
        force = true;
      };
    };
  };
}
