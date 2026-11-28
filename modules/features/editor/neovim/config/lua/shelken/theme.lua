local M = {}

function M.setup(nix)
  if not nix or not nix.flavor then
    return
  end

  local integrations = {}
  if nix.languages then
    for _, name in ipairs({
      "blink_cmp",
      "flash",
      "gitsigns",
      "grug_far",
      "markview",
      "mini",
      "noice",
      "snacks",
      "which_key",
    }) do
      integrations[name] = { enabled = true }
    end
  end

  require("catppuccin").setup({
    flavour = nix.flavor,
    transparent_background = true,
    integrations = integrations,
  })
  vim.cmd.colorscheme("catppuccin")
end

return M
