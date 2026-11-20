{
  flake.modules.homeManager.ai =
    {
      config,
      mylib,
      ...
    }:
    {
      config = {
        home.file.".local/bin/spawn-subagent" =
          mylib.mkConfigFile config ../skills/subagent-policy/spawn-subagent;

        home.file.".gemini/config/plugins/spawn-subagent" = mylib.mkConfigFile config ./agy-plugin;

        shelken.dev.sandbox.hostCommands.spawn-subagent =
          "spawn-subagent 在宿主终端 (Herdr/Kitty) 编排子代理，沙箱内无法访问宿主终端 multiplexer";
      };
    };
}
