# 用户账号：家目录与默认 shell（NixOS 侧账号在 features 的 nix/user-account）
# 所有 darwin 主机都需要 → darwin.core
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.users ];

  flake.modules.darwin.users.imports = [ ./_module.nix ];
}
