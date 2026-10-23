# Kitty 终端：配置 + 应用本体都由 HM programs.kitty 提供（nixpkgs）
{ config, ... }:
{
  # 跨平台（nixpkgs 应用 + 无 darwin 专属安装），gui 角色全覆盖保持原覆盖范围
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.kitty ];
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.kitty ];

  flake.modules.homeManager.kitty = import ./_kitty-hm.nix;
}
