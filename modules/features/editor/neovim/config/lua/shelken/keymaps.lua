-- 不依赖插件的键位，neovim-minimal 也有；沿用 AstroNvim 习惯
local map = vim.keymap.set

map("n", "<leader>w", "<cmd>write<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit window" })
map("n", "<leader>c", "<cmd>bdelete<cr>", { desc = "Close buffer" })
map("n", "L", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "H", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
map("n", "<leader>/", "gcc", { remap = true, desc = "Toggle comment line" })
map("x", "<leader>/", "gc", { remap = true, desc = "Toggle comment" })
map("n", "gl", vim.diagnostic.open_float, { desc = "Hover diagnostics" })
map("n", "<Esc>", "<cmd>nohlsearch<cr>")
