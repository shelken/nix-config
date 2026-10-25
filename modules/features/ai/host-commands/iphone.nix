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
      # iphone 与 plumesign 只适用 macOS，Linux 主机不导入这组配置
      config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        # iphone 与 skills 同源，软链到工作树源码即时生效
        home.file.".local/bin/iphone" =
          mylib.mkConfigFile config ../skills/iphone-use-best-practice/scripts/iphone;

        # go-ios 与 rcodesign 由 nix 提供，plumesign 由 mise 固定版本。
        # plumesign 是 macOS 二进制且只在宿主使用，不登记到 shelken.dev.tools（ADR 0003）
        home.packages = [
          pkgs.go-ios
          pkgs.rcodesign
        ];

        programs.mise.globalConfig.tools."github:khcrysalis/Impactor" = {
          version = "2.7.2";
          asset_pattern = "plumesign-macos-universal";
          rename_exe = "plumesign";
        };

        shelken.dev.sandbox.hostCommands.iphone = "iphone 经 USB 控制宿主连接的 iPhone，沙箱内没有 USB 设备";
      };
    };
}
