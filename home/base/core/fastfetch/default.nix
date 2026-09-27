{ ... }:
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
}
