# fastfetch：mise 安装 + 配置软链
{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.fastfetch ];

  flake.modules.homeManager.fastfetch =
    { config, mylib, ... }:
    {
      # 编译太久
      # programs.fastfetch = {
      #   enable = true;
      # };
      # renovate: datasource=github-releases depName=fastfetch-cli/fastfetch
      programs.mise.globalConfig.tools.fastfetch = "2.71.0";
      xdg.configFile = {
        "fastfetch/config.jsonc" = {
          source = ./config.jsonc;
        };
      };
    };
}
