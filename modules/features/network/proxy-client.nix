# 网络代理客户端（Loon, SFM）
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.proxy-client ];

  flake.modules.darwin.proxy-client.homebrew.casks = [
    # "loon"
    "sfm"
  ];
}
