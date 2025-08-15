local wezterm = require('wezterm')

local previous_background = nil

local command = {
    brief = "Toggle Terminal Transparency",
    icon = "md_circle_opacity",
    action = wezterm.action_callback(function(window)
        local overrides = window:get_config_overrides() or {}

        if not overrides.window_background_opacity or overrides.window_background_opacity == 1.0 then
            overrides.window_background_opacity = 0.8
            previous_background = overrides.background
            overrides.background = {}
        else
            overrides.window_background_opacity = 1.0
            overrides.background = previous_background
            previous_background = nil
        end

        window:set_config_overrides(overrides)
    end),
}


return command