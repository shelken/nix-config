{
  flake.modules.darwin.ai.homebrew = {
    # computer-use 用 media-control 判断系统是否在播放媒体
    brews = [ "media-control" ];
    # cua-driver 是 CuaDriver.app 里的二进制；官方不再通过 pip/mise 分发
    casks = [ "cuadriver" ];
  };

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

        shelken.dev.sandbox.hostCommands.computer-use = "computer-use 控制宿主 macOS 图形界面，沙箱内无法访问宿主窗口";
      };
    };
}
