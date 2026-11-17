# 1Password 桌面 App；CLI 由 secrets 功能随 sec-run 安装
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin."1password" ];

  flake.modules.darwin."1password".homebrew.casks = [ "1password" ];
}
