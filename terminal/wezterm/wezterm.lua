local wezterm = require 'wezterm'

local wallpaperFolder = 'C:/Users/abeau/OneDrive/Pictures/Backgrounds/William'

local function get_launch_menu()
    local launch_menu = {}

    if wezterm.target_triple == 'x86_64-pc-windows-msvc' then
        -- Windows-specific commands
        table.insert(launch_menu, {
            label = "PowerShell 7",
            args = {"pwsh.exe", "-NoLogo"}
        })
        table.insert(launch_menu, {
            label = "PowerShell",
            args = {"powershell.exe", "-NoLogo"}
        })
        table.insert(launch_menu, {
            label = "Git Bash",
            args = {"bash.exe", "-i", "-l"}
        })
        table.insert(launch_menu, {
            label = "Command Prompt",
            args = {"cmd.exe"}
        })

    elseif wezterm.target_triple == 'x86_64-apple-darwin' then
        -- macOS-specific commands
        table.insert(launch_menu, {
            label = "zsh",
            args = {"zsh", "-l"}
        })
        table.insert(launch_menu, {
            label = "bash",
            args = {"bash", "--login"}
        })

    elseif wezterm.target_triple:find('linux') then
        -- Linux-specific commands
        table.insert(launch_menu, {
            label = "bash",
            args = {"bash", "--login"}
        })
        table.insert(launch_menu, {
            label = "zsh",
            args = {"zsh", "-l"}
        })
    end

    return launch_menu
end

local launch_menu = get_launch_menu()

local dimmer = {
    brightness = 0.1
}

local config = {
    launch_menu = launch_menu,
    default_prog = launch_menu[1].args,
    color_scheme = 'Catppuccin Mocha',
    window_decorations = 'RESIZE',
    font = wezterm.font("JetBrainsMono Nerd Font Mono", {
        weight = "Bold",
        stretch = "Normal",
        style = "Normal"
    }),
    font_size = 13,
    -- enable_tab_bar = false,
    use_fancy_tab_bar = false,
    tab_bar_at_bottom = true,
    background = {{
        source = {
            File = os.getenv("WEZ_BG_PATH")
        },
        hsb = dimmer
    }}
}

local act = wezterm.action
config.mouse_bindings = {{
    event = {
        Down = {
            streak = 1,
            button = "Right"
        }
    },
    mods = "NONE",
    action = wezterm.action_callback(function(window, pane)
        local has_selection = window:get_selection_text_for_pane(pane) ~= ""
        if has_selection then
            window:perform_action(act.CopyTo("ClipboardAndPrimarySelection"), pane)
            window:perform_action(act.ClearSelection, pane)
        else
            window:perform_action(act({
                PasteFrom = "Clipboard"
            }), pane)
        end
    end)
}}

return config
