# proxychains：代理客户端命令行穿透配置（~/.proxychains/proxychains.conf）
# 所有 darwin 主机都可能有 CLI 代理穿透需求（brews 里的 proxychains-ng 在 homebrew 基础里）→ darwin.core
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.proxy ];

  flake.modules.homeManager.proxy.imports = [ ./_module.nix ];
}
