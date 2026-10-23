# Final Cut Pro 试用重置脚本：脚本所有 darwin 主机都有（原 home/darwin/scripts）
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.reset-fcp-trial ];

  flake.modules.homeManager.reset-fcp-trial = import ./_script.nix;
}
