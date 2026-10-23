# dev 选项：cloud-native（home/base/core/dev.nix 迁入）
# cloud-native 只在 mio 开启，功能本体随 mio 走（features/dev/cloud-native.nix），
# 但选项保留为参数：需要时其他主机也能打开工具集
{
  flake.modules.homeManager.dev-options =
    { lib, ... }:
    {
      options.shelken.dev.cloud-native = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether or not use to enable.";
        };
      };
    };
}
