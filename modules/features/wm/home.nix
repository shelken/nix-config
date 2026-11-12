{
  flake.modules.homeManager.wm =
    {
      lib,
      mylib,
      config,
      osConfig,
      ...
    }:
    let
      inherit (osConfig.shelken.wm) manager;
    in
    lib.mkIf (manager == "omniwm") {
      launchd.agents.omniwm = mylib.mkLaunchCommand {
        name = "omniwm";
        commandFile = "/Applications/OmniWM.app/Contents/MacOS/OmniWM";
        domain = "gui";
      };

      xdg.configFile = {
        "omniwm/settings.toml" = mylib.mkConfigFile config ./omniwm/settings.toml;
        "omniwm/shell/shell.toml" = mylib.mkConfigFile config ./omniwm/shell/shell.toml;
        "omniwm/shell/widgets/openusage" = mylib.mkConfigFile config ./omniwm/shell/widgets/openusage;
      };
    };
}
