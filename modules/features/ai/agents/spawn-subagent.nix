{
  flake.modules.homeManager.ai =
    {
      config,
      mylib,
      ...
    }:
    {
      config = {
        # spawn-subagent 与 skills 同源，软链到工作树源码即时生效
        home.file = {
          ".local/bin/spawn-subagent" = mylib.mkConfigFile config ../skills/subagent-policy/spawn-subagent;
          ".gemini/config/plugins/spawn-subagent" = mylib.mkConfigFile config ./agy-plugin;
        };

        shelken.dev.sandbox.hostCommands.spawn-subagent =
          "spawn-subagent 在宿主终端 (Herdr/Kitty) 编排子代理，沙箱内无法访问宿主终端 multiplexer";
      };
    };
}
