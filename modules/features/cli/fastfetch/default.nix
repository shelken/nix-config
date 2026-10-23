# fastfetch：mise 安装 + 配置软链（home/base/core/fastfetch 迁入）
{
  flake.modules.homeManager.fastfetch =
    { config, mylib, ... }:
    {
      # 编译太久
      # programs.fastfetch = {
      #   enable = true;
      # };
      programs.mise.globalConfig.tools.fastfetch = "2.68";
      xdg.configFile = {
        "fastfetch/config.jsonc" = {
          source = ./config.jsonc;
        };
      };
    };
}
