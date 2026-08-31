{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.wm.omniwm;

  omniwmTomlPath = "${config.home.homeDirectory}/nix-config/home/darwin/wm/omniwm/settings.toml";
in
{
  options.shelken.wm.omniwm = {
    enable = mkBoolOpt false "Whether or not to enable omniwm.";
  };

  config = mkIf cfg.enable {
    launchd.agents.omniwm = mylib.mkLaunchCommand {
      name = "omniwm";
      commandFile = "/Applications/OmniWM.app/Contents/MacOS/OmniWM";
      domain = "gui";
    };

    xdg.configFile = {
      "omniwm/settings.toml" = {
        source = config.lib.file.mkOutOfStoreSymlink omniwmTomlPath;
        force = true;
      };
    };
  };
}
