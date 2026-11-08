{
  flake.modules.homeManager.ai =
    {
      lib,
      config,
      pkgs,
      mylib,
      ...
    }:
    {
      # iphone 依赖 macOS 上的 Pinky，Linux 主机不导入这组配置
      config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        # iphone 与 skills 同源，软链到工作树源码即时生效
        home.file.".local/bin/iphone" =
          mylib.mkConfigFile config ../skills/iphone-use-best-practice/scripts/iphone;

        shelken.dev.sandbox.hostCommands.iphone = "iphone 经宿主上的 Pinky 控制 USB 连接的 iPhone，沙箱内没有 USB 设备";
      };
    };
}
