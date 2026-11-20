{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.fastfetch ];

  flake.modules.homeManager.fastfetch =
    { pkgs, ... }:
    {
      programs.fastfetch = {
        enable = true;
        # 完整版只是多包一层 vulkan 等图形库：darwin 上带进 apple-sdk 与 MoltenVK（约 450 MiB），
        # Linux 上带进 libglvnd、ddcutil、xfconf 等；服务器与终端里用不到
        package = pkgs.fastfetch-unwrapped;
      };
      xdg.configFile = {
        "fastfetch/config.jsonc" = {
          source = ./config.jsonc;
        };
      };
    };
}
