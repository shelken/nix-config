# Neovim：最小变体（yuuko 用，只有 nvim 本体不带配置）
# 原 home/base/core/neovim；完整变体见 features/editor/neovim
# 两者均声明 shelken.neovim.minimal（true / false），同一台主机只会导入其中一个
{
  flake.modules.homeManager.neovim-minimal =
    { lib, ... }:
    {
      options.shelken.neovim.minimal = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "最小化安装nvim（不带配置）";
      };

      programs.neovim = {
        enable = true;

        viAlias = true;
        vimAlias = true;
      };
    };
}
