# Nix 运行时基础：Determinate Nix 共存配置、registry 指向本 flake 锁定的 nixpkgs
# 所有 darwin 主机都需要 → darwin.core
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.nix ];

  flake.modules.darwin.nix.imports = [ ./_module.nix ];
}
