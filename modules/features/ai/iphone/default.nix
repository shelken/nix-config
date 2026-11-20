{ config, inputs, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.iphone ];

  flake.modules.homeManager.iphone =
    { config, mylib, ... }:
    {
      shelken.dev.ai.skills = [
        ./iphone-use-best-practice
        "${inputs.swipt-skills}/skills/swipt"
      ];

      home.file.".local/bin/iphone" = mylib.mkConfigFile config ./iphone-use-best-practice/scripts/iphone;

      shelken.dev.sandbox.hostCommands.iphone = "iphone 经宿主上的 Pinky 控制 iPhone，Pinky 只在宿主运行";

      programs.mise.globalConfig.tools."npm:@swipt/cli" = {
        version = "latest";
        minimum_release_age = "0h";
        allow_low_downloads = true;
      };
      shelken.dev.sandbox.hostCommands.swipt = "swipt 侧载并连接 USB/局域网上的 iPhone，依赖宿主的 Xcode 与网络，沙箱内不可用";
    };
}
