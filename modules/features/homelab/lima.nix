# Lima：Linux 虚拟机，供 homelab 主机跑容器与服务
{ config, ... }:
{
  flake.modules.darwin.homelab.imports = [ config.flake.modules.darwin.lima ];

  flake.modules.darwin.lima.homebrew.brews = [ "lima" ];
}
