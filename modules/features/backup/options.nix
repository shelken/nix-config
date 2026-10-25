# 备份接口选项：backupPaths / app / ignores
# 「会被其他功能写入的接口选项必须声明在 core」（ADR 0004）；
# NixOS 主机上也有写入 shelken.backup.app 的可能，darwin.core 与 nixos.core 都要拿到
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.backup-options ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.backup-options ];

  flake.modules.homeManager.backup-options = import ./_options.nix;
}
