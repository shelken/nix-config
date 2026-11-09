# 会话归档接口选项：app / afterDays / keyFile
# 「会被其他功能写入的接口选项必须声明在 core」（ADR 0004）；
# NixOS 主机上的 omp/pi 也会写 app，darwin.core 与 nixos.core 都要拿到
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.session-archive-options ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.session-archive-options ];

  flake.modules.homeManager.session-archive-options = import ./_options.nix;
}
