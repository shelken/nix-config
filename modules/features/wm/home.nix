{
  flake.modules.homeManager.wm =
    {
      lib,
      mylib,
      config,
      pkgs,
      osConfig,
      ...
    }:
    let
      inherit (osConfig.shelken.wm) manager;

      scripts = [
        "get-app-bundleid"
        "open-terminal-in-finder-path"
        "pip-move"
      ];

      writeShellBin =
        name: pkgs.writeShellScriptBin "as-${name}" (builtins.readFile ./aerospace/scripts/${name}.sh);
    in
    lib.mkMerge [
      (lib.mkIf (manager == "aerospace") {
        home.packages = map writeShellBin scripts;
        xdg.configFile = {
          "aerospace/aerospace.toml" = mylib.mkConfigFile config ./aerospace/aerospace.toml;
        };
      })
      (lib.mkIf (manager == "omniwm") {
        launchd.agents.omniwm = mylib.mkLaunchCommand {
          name = "omniwm";
          commandFile = "/Applications/OmniWM.app/Contents/MacOS/OmniWM";
          domain = "gui";
        };

        xdg.configFile = {
          "omniwm/settings.toml" = mylib.mkConfigFile config ./omniwm/settings.toml;
        };
      })
    ];
}
