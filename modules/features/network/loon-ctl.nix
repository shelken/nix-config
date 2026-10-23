# loon-ctl：查询 Loon DNS 记录的 CLI（脚本所有 darwin 主机都有）
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.loon-ctl ];

  flake.modules.homeManager.loon-ctl.imports = [ ./_loon-ctl.nix ];
}
