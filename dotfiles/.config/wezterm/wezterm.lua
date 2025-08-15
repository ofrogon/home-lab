local wezterm = require("wezterm")
local constants = require("constants")
local colors = require("colors")
local commands = require("commands")

local config = wezterm.config_builder()

--- Font settings
config.font = wezterm.font("JetBrainsMono Nerd Font Mono")
config.font_size = 14.0
config.line_height = 1.2
config.cell_width = 1.0

-- Theme
function scheme_for_appearance(appearance)
	if appearance:find("Dark") then
		return "Catppuccin Macchiato"
	else
		return "Catppuccin Latte"
	end
end

config.color_scheme = scheme_for_appearance(wezterm.gui.get_appearance())

-- Appearance
-- config.window_decorations = "RESIZE"
config.background = {
	{
		source = {
			File = constants.bg_image,
		},
		hsb = colors.hsb_darker,
		vertical_align = "Middle",
		horizontal_align = "Center",
	},
}
config.window_padding = {
	left = 0,
	right = 0,
	top = 0,
	bottom = 0,
}
config.hide_tab_bar_if_only_one_tab = true
config.window_close_confirmation = "NeverPrompt"

-- Performance
config.enable_scroll_bar = false
config.max_fps = 60

-- Custom Commands
wezterm.on("augment-command-palette", function(window)
	return commands
end)

return config
