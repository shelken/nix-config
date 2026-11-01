local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.scrolloff = 8
opt.wrap = false
opt.splitright = true
opt.splitbelow = true
opt.clipboard = "unnamedplus"
opt.ignorecase = true
opt.smartcase = true
opt.undofile = true
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.updatetime = 300
opt.timeoutlen = 400
opt.confirm = true
-- 内置补全：边打字边弹出当前 buffer 的词，不依赖插件
opt.autocomplete = true
opt.completeopt = { "menuone", "noselect", "popup" }

vim.filetype.add({
  pattern = {
    -- Neovim 不识别 helm 模板；helm_ls 只在 filetype=helm 时启动
    [".*/templates/.*%.ya?ml"] = function(path)
      return vim.fs.root(path, "Chart.yaml") and "helm" or nil
    end,
    [".*/templates/.*%.tpl"] = "helm",
  },
})

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("shelken_treesitter", {}),
  callback = function(args)
    if pcall(vim.treesitter.start, args.buf) then
      vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
  group = vim.api.nvim_create_augroup("shelken_yank", {}),
  callback = function()
    vim.hl.on_yank()
  end,
})
