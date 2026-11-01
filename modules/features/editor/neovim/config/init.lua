-- 插件由 Home Manager 装进 packpath 并在启动时加载；这里只做配置
vim.g.mapleader = " "
vim.g.maplocalleader = ","

require("vim._core.ui2").enable({})

require("shelken.options")
require("shelken.lsp")
require("shelken.plugins")
