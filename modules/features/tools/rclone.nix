# rclone 挂载依赖（macfuse）
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.rclone-tools ];

  flake.modules.darwin.rclone-tools.homebrew.casks = [ "macfuse" ];
}
