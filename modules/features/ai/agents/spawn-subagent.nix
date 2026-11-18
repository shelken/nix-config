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
        home.file.".local/bin/spawn-subagent" =
          mylib.mkConfigFile config ../skills/subagent-policy/spawn-subagent;

        # agy 子代理的正文注入、工具限制与回传都靠这个插件的 hook；未经 spawn-subagent 启动的 agy 不受影响
        home.file.".gemini/config/plugins/spawn-subagent" = mylib.mkConfigFile config ./agy-plugin;

        shelken.dev.sandbox.hostCommands.spawn-subagent =
          "spawn-subagent 在宿主终端 (Herdr/Kitty) 编排子代理，沙箱内无法访问宿主终端 multiplexer";
      };
    };
}
