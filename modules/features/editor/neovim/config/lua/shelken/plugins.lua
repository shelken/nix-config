local map = vim.keymap.set

require("mini.icons").setup()
require("mini.icons").mock_nvim_web_devicons()

local snacks = require("snacks")
snacks.setup({
  picker = { enabled = true },
  input = { enabled = true },
  lazygit = { enabled = true },
})
map("n", "<leader>ff", function() snacks.picker.files() end, { desc = "Find files" })
map("n", "<leader>fw", function() snacks.picker.grep() end, { desc = "Grep" })
map("n", "<leader>fb", function() snacks.picker.buffers() end, { desc = "Buffers" })
map("n", "<leader>fr", function() snacks.picker.recent() end, { desc = "Recent files" })
map("n", "<leader>fh", function() snacks.picker.help() end, { desc = "Help" })
map("n", "<leader>fk", function() snacks.picker.keymaps() end, { desc = "Keymaps" })
map("n", "<leader>fd", function() snacks.picker.diagnostics() end, { desc = "Diagnostics" })
map("n", "<leader>fs", function() snacks.picker.lsp_symbols() end, { desc = "Document symbols" })
map("n", "<leader>f<CR>", function() snacks.picker.resume() end, { desc = "Resume last picker" })
map("n", "<leader>gg", function() snacks.lazygit() end, { desc = "Lazygit" })

local gitsigns = require("gitsigns")
gitsigns.setup()
map("n", "]h", function() gitsigns.nav_hunk("next") end, { desc = "Next hunk" })
map("n", "[h", function() gitsigns.nav_hunk("prev") end, { desc = "Prev hunk" })
map("n", "<leader>gp", gitsigns.preview_hunk, { desc = "Preview hunk" })
map("n", "<leader>gr", gitsigns.reset_hunk, { desc = "Reset hunk" })
map("n", "<leader>gb", gitsigns.blame_line, { desc = "Blame line" })

require("grug-far").setup()
map("n", "<leader>sr", "<cmd>GrugFar<cr>", { desc = "Search and replace" })

require("yazi").setup({ open_for_directories = true })
vim.g.loaded_netrwPlugin = 1
map("n", "<leader>e", "<cmd>Yazi<cr>", { desc = "Yazi (current file)" })
map("n", "<leader>E", "<cmd>Yazi cwd<cr>", { desc = "Yazi (cwd)" })

-- s 留给 flash，surround 用 gs 前缀
require("mini.surround").setup({
  mappings = {
    add = "gsa",
    delete = "gsd",
    replace = "gsr",
    find = "gsf",
    find_left = "gsF",
    highlight = "gsh",
    update_n_lines = "gsn",
  },
})

local flash = require("flash")
flash.setup()
map({ "n", "x", "o" }, "s", flash.jump, { desc = "Flash" })
map({ "n", "x", "o" }, "S", flash.treesitter, { desc = "Flash treesitter" })

map("n", "<leader>w", "<cmd>write<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit window" })
map("n", "<leader>c", "<cmd>bdelete<cr>", { desc = "Close buffer" })
map("n", "<Esc>", "<cmd>nohlsearch<cr>")

require("which-key").setup({
  spec = {
    { "<leader>f", group = "find" },
    { "<leader>g", group = "git" },
    { "<leader>l", group = "lsp" },
    { "<leader>s", group = "search" },
    { "gs", group = "surround" },
  },
})
