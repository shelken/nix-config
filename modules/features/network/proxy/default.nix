# 代理：proxychains 命令行穿透配置（所有 darwin 主机 → darwin.core，proxychains-ng 在 homebrew 基础里）
# 与代理客户端 SFM（只给 workstation）
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.proxy ];
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.proxy-client ];

  flake.modules.homeManager.proxy.home.file.".proxychains/proxychains.conf".source =
    ./proxychains.conf;

  flake.modules.darwin.proxy-client.homebrew.casks = [
    # "loon"
    "sfm"
  ];
}
