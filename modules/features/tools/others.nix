# 其他系统工具（AltServer）
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.tools-others ];

  flake.modules.darwin.tools-others.homebrew.casks = [ "altserver" ];
}
