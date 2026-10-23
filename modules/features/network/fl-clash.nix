# FL-Clash: Clash GUI 代理客户端
{ config, ... }:
{
  flake.modules.darwin.homelab.imports = [ config.flake.modules.darwin.fl-clash ];

  flake.modules.darwin.fl-clash.homebrew.casks = [ "fl-clash" ];
}
