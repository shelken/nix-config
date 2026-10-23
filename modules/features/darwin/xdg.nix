# xdg：HM 的 xdg.enable（darwin 上提供 XDG 基础目录）
# 原 home/darwin/default.nix 迁入；所有 darwin 主机 → darwin.core
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.xdg ];

  flake.modules.homeManager.xdg = {
    xdg.enable = true;
  };
}
