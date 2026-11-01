-- 外观与补全：两层都有，不依赖语言工具（插件列表见 default.nix 的 neovim-minimal）

require("mini.icons").setup()
require("mini.icons").mock_nvim_web_devicons()

-- 居中的命令行输入框（cmdline_popup），沿用原 AstroNvim 的 noice 配置
require("noice").setup({
  presets = { command_palette = false, long_message_to_split = true },
})

-- markdown 渲染（标题、列表、代码块、表格）
require("markview").setup()

-- 没有 LSP 时补全 buffer 里的词和路径；完整层有 LSP 时自动加上 LSP 候选
require("blink.cmp").setup({
  keymap = {
    preset = "enter",
    ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
    ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
  },
  completion = { documentation = { auto_show = true } },
  signature = { enabled = true },
  -- 命令行补全默认要按 Tab 才弹出；改为边输边弹，Tab 确认（原 cmp-cmdline 习惯）
  cmdline = {
    keymap = {
      preset = "cmdline",
      ["<Tab>"] = { "select_and_accept", "show_and_insert" },
      ["<Down>"] = { "select_next", "fallback" },
      ["<Up>"] = { "select_prev", "fallback" },
    },
    completion = { menu = { auto_show = true } },
  },
})
