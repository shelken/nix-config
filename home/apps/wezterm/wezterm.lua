local wezterm = require("wezterm")
local config = {
	font_size = 18,
	-- font = wezterm.font("JetBrainsMonoNL Nerd Font", { weight = "Regular" }),
	font = wezterm.font("FiraCode Nerd Font Mono", { weight = "Medium" }),
	-- font = wezterm.font("FiraCode Nerd Font Mono", { weight = "Regular" }),
	-- color_scheme = "Catppuccin Mocha",
	color_scheme = "Catppuccin Macchiato", -- or Mocha, Frappe, Latte, Macchiato

	use_fancy_tab_bar = false,
	hide_tab_bar_if_only_one_tab = true,
	window_decorations = "RESIZE",
	show_new_tab_button_in_tab_bar = false,
	window_background_opacity = 0.88,
	macos_window_background_blur = 64,
	-- text_background_opacity = 0.9,
	-- 平铺时希望false
	adjust_window_size_when_changing_font_size = false,
	window_padding = {
		left = 10,
		right = 10,
		top = 12,
		bottom = 0,
	},
}

return config
