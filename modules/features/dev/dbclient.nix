# 数据库客户端（dbx）
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.dbclient ];

  flake.modules.darwin.dbclient.homebrew.casks = [ "dbx" ];
}
