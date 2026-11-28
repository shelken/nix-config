vim.g.mapleader = " "
vim.g.maplocalleader = ","

local ok, nix = pcall(require, "nix_config")
nix = ok and nix or {}

require("shelken.options")
require("shelken.keymaps")
require("shelken.theme").setup(nix)
if nix.languages then
  require("shelken.ui")
  require("shelken.lsp")
  require("shelken.plugins")
end
