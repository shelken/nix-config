# LM Studio：本地模型推理服务，由兼做服务器的 homelab 主机提供
{ config, ... }:
{
  flake.modules.darwin.homelab.imports = [ config.flake.modules.darwin.lm-studio ];

  flake.modules.darwin.lm-studio.homebrew.casks = [ "lm-studio" ];
}
