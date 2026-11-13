# ai 是跑 agent 的机器都需要的运行时；只在工作站用的能力是各自独立的功能（ADR 0008）
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.ai ];
}
