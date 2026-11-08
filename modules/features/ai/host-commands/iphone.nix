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

        # Swipt CLI：侧载 Swipt 到 iPhone 并连接其开发者 API；npm 上只有 nightly，需跟最新
        # 包名首发不足 30 天会被 aube 拦截；已核对官方文档与源码仓库，只对这个包放行
        programs.mise.globalConfig.tools."npm:@swipt/cli" = {
          version = "latest";
          minimum_release_age = "0h";
          allow_low_downloads = true;
        };
        shelken.dev.sandbox.hostCommands.swipt = "swipt 侧载并连接 USB/局域网上的 iPhone，依赖宿主的 Xcode 与网络，沙箱内不可用";
      };
    };
}
