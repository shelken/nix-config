-- 插件由 Home Manager 装进 packpath 并在启动时加载；这里只做配置
-- neovim-minimal 只有 options；完整层由 Nix 注入 vim.g.nix_languages，并装好下面两个文件用到的插件
vim.g.mapleader = " "
vim.g.maplocalleader = ","

require("shelken.options")
require("shelken.keymaps")
if vim.g.nix_languages then
  require("shelken.lsp")
  require("shelken.plugins")
else
  -- 完整层用 noice（居中命令行），两者接管同一组 UI 事件，只能开一个
  require("vim._core.ui2").enable({})
end
