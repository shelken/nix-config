{
  pkgs,
  lib,
  config,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };
in
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    home.file = {
      ".config/ponytail/config.json".source = jsonFormat.generate "ponytail-config.json" {
        defaultMode = "full";
        hideStatus = true;
        quietStartup = true;
      };

      ".config/rpiv-web-tools/config.json".source = jsonFormat.generate "rpiv-web-tools-config.json" {
        interceptors = {
          github = true;
        };
        provider = "exa";
      };
    };
  };
}
