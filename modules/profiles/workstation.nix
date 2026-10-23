# workstation：gui + 日常主力机才需要的个人工作流功能
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.gui ];
}
