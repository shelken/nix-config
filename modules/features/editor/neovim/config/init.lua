-- 插件由 Home Manager 装进 packpath 并在启动时加载；这里只做配置
-- 两层都加载 options / keymaps / ui；完整层由 Nix 注入 vim.g.nix_languages，并装好 lsp / plugins 用到的插件
vim.g.mapleader = " "
vim.g.maplocalleader = ","

require("shelken.options")
require("shelken.keymaps")
require("shelken.ui")
if vim.g.nix_languages then
  require("shelken.lsp")
  require("shelken.plugins")
end
