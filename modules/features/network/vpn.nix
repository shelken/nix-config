# 组网客户端：Tailscale、ZeroTier
{ config, ... }:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.vpn ];

  flake.modules.darwin.vpn.homebrew.casks = [
    "tailscale-app"
    "zerotier-one"
  ];
}
