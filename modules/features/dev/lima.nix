# Lima：Linux 虚拟机，供开发与容器使用
{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.lima ];

  flake.modules.darwin.lima.homebrew.brews = [ "lima" ];
}
