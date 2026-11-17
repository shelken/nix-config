# 网络排查小工具：q（DNS 查询）、nali（给 IP 标注地理位置，如 `traceroute 1.1.1.1 | nali`）
# 开发机 → tui
{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.net-tools ];

  flake.modules.homeManager.net-tools =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        q
        nali
      ];
    };
}
