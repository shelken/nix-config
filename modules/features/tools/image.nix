# 图片处理与图床工具（ImageOptim, uPic）
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.image-tools ];

  flake.modules.darwin.image-tools.homebrew.casks = [
    "imageoptim"
    "upic"
  ];
}
