{ config, ... }:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.wm ];

  flake.modules.darwin.wm =
    { lib, config, ... }:
    let
      inherit (config.shelken.wm) manager;
    in
    {
      options.shelken.wm.manager = lib.mkOption {
        type = lib.types.enum [ "omniwm" ];
        default = "omniwm";
        description = "选择使用的平铺窗口管理器";
      };

      config = lib.mkIf (manager == "omniwm") {
        homebrew = {
          taps = [
            {
              name = "BarutSRB/tap";
              trusted = true;
            }
          ];
          casks = [ "omniwm" ];
        };
      };
    };

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
