# Neovim 本体：所有主机都有的最小安装（nvim、vi/vim 别名，不带配置）
# 完整配置见 features/editor/neovim（tui 及以上的 HM 角色）
# 两个功能同时生效：本文件只开 nvim，full 版本按 shelken.neovim.minimal 决定是否装配置与工具链
{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.neovim-minimal ];

  flake.modules.homeManager.neovim-minimal = {
    programs.neovim = {
      enable = true;

      viAlias = true;
      vimAlias = true;
    };
  };
}
