{
  # computer-use 用 media-control 判断系统是否在播放媒体
  flake.modules.darwin.ai.homebrew.brews = [ "media-control" ];

  flake.modules.homeManager.ai =
    {
      config,
      mylib,
      ...
    }:
    {
      config = {
        # computer-use 与 skills 同源，软链到工作树源码即时生效
        home.file.".local/bin/computer-use" =
          mylib.mkConfigFile config ../skills/computer-use-best-practice/scripts/computer-use.ts;

        # cua-cli 提供 computer-use 调用的 cua-driver
        programs.mise.globalConfig.tools."pipx:cua-cli" = "0.1";

        shelken.dev.sandbox.hostCommands.computer-use = "computer-use 控制宿主 macOS 图形界面，沙箱内无法访问宿主窗口";
      };
    };
}
