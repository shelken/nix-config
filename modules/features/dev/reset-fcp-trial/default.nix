# Final Cut Pro 试用重置脚本：服务的应用（Final Cut Pro）只在 mio 装机，跟 IDE 等 workstation 应用同级
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.reset-fcp-trial ];

  flake.modules.homeManager.reset-fcp-trial = import ./_script.nix;
}
