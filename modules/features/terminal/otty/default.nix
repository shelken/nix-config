# Otty 终端（已存档不使用）：仅 HM 配置；应用本体手动安装，仓库无安装声明
{ config, ... }:
{
  # 应用无角色归属（手动安装、无安装功能），配置保持原 gui 全覆盖
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.otty ];
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.otty ];

  flake.modules.homeManager.otty = import ./_otty-hm.nix;
}
