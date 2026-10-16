{
  config,
  lib,
  pkgs,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };
in
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    home.file.".microsandbox/config.json".source = jsonFormat.generate "microsandbox-config.json" {
      version = 1;
      home = "${config.home.homeDirectory}/Data/sandboxes/msb";
      paths = {
        cache = "${config.home.homeDirectory}/.cache/microsandbox";
      };
    };
  };
}
