# Telegram 即时通讯客户端
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.telegram ];

  flake.modules.darwin.telegram.homebrew.casks = [ "telegram" ];
}
