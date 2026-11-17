# nix-index：按文件名查哪个包提供，并在命令找不到时提示
# 所有 darwin 主机 → darwin.core
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.nix-index ];

  flake.modules.homeManager.nix-index.programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };
}
