# workstation：desktop + 日常主力机才需要的个人工作流功能
{ config, ... }:
let
  inherit (config.flake.modules) darwin;
in
{
  flake.modules.darwin.workstation.imports = [ darwin.desktop ];
}
