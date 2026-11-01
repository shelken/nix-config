-- 语言表由 Nix 生成（见 _languages.nix）；裸跑 nvim 时为空
local languages = vim.g.nix_languages or { lsp = {}, formatters = {}, linters = {} }

vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
})

vim.lsp.config("jsonls", {
  settings = {
    json = { schemas = require("schemastore").json.schemas(), validate = { enable = true } },
  },
})
vim.lsp.config("yamlls", {
  settings = {
    yaml = {
      schemaStore = { enable = false, url = "" },
      schemas = require("schemastore").yaml.schemas(),
    },
  },
})
vim.lsp.enable(languages.lsp)

require("blink.cmp").setup({
  keymap = {
    preset = "enter",
    ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
    ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
  },
  completion = { documentation = { auto_show = true } },
  signature = { enabled = true },
})

local conform = require("conform")
conform.setup({
  formatters_by_ft = languages.formatters,
  format_on_save = { timeout_ms = 1000 },
})
vim.keymap.set({ "n", "x" }, "<leader>lf", function()
  conform.format({ lsp_format = "fallback" })
end, { desc = "Format" })

local lint = require("lint")
lint.linters_by_ft = languages.linters
-- actionlint 只认识 GitHub Actions workflow，不能跑在任意 yaml 上
local path_only = { actionlint = "/%.github/workflows/" }
-- 用 FileType 而非 BufReadPost：init.lua 里的 BufReadPost 先于 filetypedetect 注册，触发时 filetype 还是空的
vim.api.nvim_create_autocmd({ "FileType", "BufWritePost" }, {
  group = vim.api.nvim_create_augroup("shelken_lint", {}),
  callback = function(args)
    local path = vim.api.nvim_buf_get_name(args.buf)
    local names = vim.tbl_filter(function(name)
      return not path_only[name] or path:find(path_only[name]) ~= nil
    end, lint.linters_by_ft[vim.bo[args.buf].filetype] or {})
    if #names > 0 then
      lint.try_lint(names)
    end
  end,
})
