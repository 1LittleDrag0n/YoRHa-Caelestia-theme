-- Extra title bar buttons on the LEFT: pin, menu, hide from screen share
-- (needs the patched hyprbars with side / active_when / active_bg_color)
-- Left buttons are placed left -> right in the order they're added here.
if hl.plugin and hl.plugin.hyprbars then
    -- Pin: turns gold while the window is pinned
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(3a342f)", fg_color = "rgb(c4b89c)", size = 14, icon = "󰐃",
        side = "left",
        active_when = "pinned", active_bg_color = "rgb(8f7c4a)",
        action = "hyprctl dispatch 'hl.dsp.window.pin()'",
    })

    -- Window menu
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(3a342f)", fg_color = "rgb(c4b89c)", size = 14, icon = "󰍜",
        side = "left",
        action = os.getenv("HOME") .. "/.local/bin/window-menu.fish",
    })

    -- Hide from screen share: turns red while the window is hidden
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(3a342f)", fg_color = "rgb(c4b89c)", size = 14, icon = "󰈉",
        side = "left",
        active_when = "no_screen_share", active_bg_color = "rgb(c0584a)",
        action = [[hyprctl dispatch 'hl.dsp.window.tag({ tag = "private" })']],
    })
end

-- Windows tagged "private" are blacked out in screenshots and screen sharing,
-- and get a dark red border as a second hint
hl.window_rule({ match = { tag = "private" }, no_screen_share = true, border_color = "rgb(8b2a2a)" })
