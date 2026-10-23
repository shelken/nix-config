# Homebrew 基础：镜像环境变量、常用 taps/brews、zsh 与终端基础包
# 所有 darwin 主机都需要 → darwin.core
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.homebrew ];

  flake.modules.darwin.homebrew.imports = [ ./_module.nix ];
}
