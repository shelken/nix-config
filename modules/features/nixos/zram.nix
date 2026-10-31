# zram：内存里压缩的 swap，不占磁盘 I/O
# 小内存服务器需要 → nixos.server
{ config, ... }:
{
  flake.modules.nixos.server.imports = [ config.flake.modules.nixos.zram ];

  flake.modules.nixos.zram = {
    zramSwap.enable = true;
  };
}
