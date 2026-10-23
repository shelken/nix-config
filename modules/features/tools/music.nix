# 音乐相关工具
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.music-tools ];

  flake.modules.darwin.music-tools.homebrew.casks = [ ];
}
