# 微信客户端
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.wechat ];

  flake.modules.darwin.wechat.homebrew.casks = [ "wechat" ];
}
