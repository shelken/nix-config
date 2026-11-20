vim.g.mapleader = " "
vim.g.maplocalleader = ","

require("shelken.options")
require("shelken.keymaps")
require("shelken.ui")
if vim.g.nix_languages then
  require("shelken.lsp")
  require("shelken.plugins")
end
