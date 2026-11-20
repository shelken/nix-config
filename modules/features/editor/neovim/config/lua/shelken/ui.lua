require("mini.icons").setup()
require("mini.icons").mock_nvim_web_devicons()

require("noice").setup({
  presets = { command_palette = false, long_message_to_split = true },
})

require("markview").setup()

require("blink.cmp").setup({
  keymap = {
    preset = "enter",
    ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
    ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
  },
  completion = { documentation = { auto_show = true } },
  signature = { enabled = true },
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
