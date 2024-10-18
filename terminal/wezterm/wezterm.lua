local wezterm = require 'wezterm'

local wallpaperFolder = 'C:/Users/abeau/OneDrive/Pictures/Backgrounds/William'

local launch_menu = {{
    label = 'PowerShell 7',
    args = {"C:/Program Files/PowerShell/7/pwsh.exe", '-NoLogo'}
}, {
    label = 'PowerShell',
    args = {"C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe", '-NoLogo'}
}, {
    label = 'Bash',
    args = {"C:/Program Files/Git/bin/bash.exe", '-i', '-l'}
}}

local dimmer = {
    brightness = 0.1
}

local config = {
    launch_menu = launch_menu,
    default_prog = {"C:/Program Files/PowerShell/7/pwsh.exe", '-NoLogo'},
    color_scheme = 'Catppuccin Mocha',
    window_decorations = 'RESIZE',
    font = wezterm.font("JetBrainsMonoNL Nerd Font Mono", {
        weight = "Bold",
        stretch = "Normal",
        style = "Normal"
    }),
    font_size = 16,
    enable_tab_bar = false,
    -- use_fancy_tab_bar = false,
    -- tab_bar_at_bottom = true,
    background = {{
        source = {
            File = os.getenv("WEZ_BG_PATH")
        },
        hsb = dimmer
    }}
}

return config
