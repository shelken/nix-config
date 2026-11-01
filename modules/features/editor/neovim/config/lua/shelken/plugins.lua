local map = vim.keymap.set

require("mini.icons").setup()
require("mini.icons").mock_nvim_web_devicons()

local snacks = require("snacks")
-- 启动画面：chafa 把 gif 实时渲染成盲文字符画；ttl = 0 不缓存，保留动画
local logo = vim.fn.stdpath("config") .. "/assets/mio.gif"
snacks.setup({
  picker = { enabled = true },
  input = { enabled = true },
  lazygit = { enabled = true },
  dashboard = {
    enabled = true,
    sections = {
      {
        section = "terminal",
        cmd = "chafa -f symbols -s 60 -c full --fg-only --symbols braille --clear " .. logo,
        width = 60,
        height = 18,
        ttl = 0,
        padding = 1,
      },
      { section = "keys", gap = 1, padding = 1 },
    },
  },
})
-- 键位沿用 AstroNvim 默认
map("n", "<leader>ff", function() snacks.picker.files() end, { desc = "Find files" })
map("n", "<leader>fw", function() snacks.picker.grep() end, { desc = "Find words" })
map("n", "<leader>fb", function() snacks.picker.buffers() end, { desc = "Find buffers" })
map("n", "<leader>fo", function() snacks.picker.recent() end, { desc = "Find old files" })
map("n", "<leader>fh", function() snacks.picker.help() end, { desc = "Find help" })
map("n", "<leader>fk", function() snacks.picker.keymaps() end, { desc = "Find keymaps" })
map("n", "<leader>f<CR>", function() snacks.picker.resume() end, { desc = "Resume previous search" })
map("n", "<leader>lD", function() snacks.picker.diagnostics() end, { desc = "Search diagnostics" })
map("n", "<leader>ls", function() snacks.picker.lsp_symbols() end, { desc = "Document symbols" })
map("n", "<leader>gg", function() snacks.lazygit() end, { desc = "Lazygit" })

local gitsigns = require("gitsigns")
gitsigns.setup()
map("n", "]g", function() gitsigns.nav_hunk("next") end, { desc = "Next Git hunk" })
map("n", "[g", function() gitsigns.nav_hunk("prev") end, { desc = "Previous Git hunk" })
map("n", "<leader>gp", gitsigns.preview_hunk, { desc = "Preview hunk" })
map("n", "<leader>gr", gitsigns.reset_hunk, { desc = "Reset hunk" })
map("n", "<leader>gb", gitsigns.blame_line, { desc = "Blame line" })

require("grug-far").setup()
map("n", "<leader>sr", "<cmd>GrugFar<cr>", { desc = "Search and replace" })

require("yazi").setup({ open_for_directories = true })
vim.g.loaded_netrwPlugin = 1
map("n", "<leader>e", "<cmd>Yazi<cr>", { desc = "Yazi (current file)" })
map("n", "<leader>-", "<cmd>Yazi<cr>", { desc = "Yazi (current file)" })
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

require("which-key").setup({
  spec = {
    { "<leader>f", group = "find" },
    { "<leader>g", group = "git" },
    { "<leader>l", group = "lsp" },
    { "<leader>s", group = "search" },
    { "gs", group = "surround" },
  },
})
