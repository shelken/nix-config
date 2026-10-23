# 网络代理客户端（Loon, SFM）
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.loon ];

  flake.modules.darwin.loon.homebrew.casks = [
    "loon"
    "sfm"
  ];
}
