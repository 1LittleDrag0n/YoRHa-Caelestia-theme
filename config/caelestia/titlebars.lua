-- Only runs once the plugin is loaded (avoids errors before that)
if hl.plugin and hl.plugin.hyprbars then
    hl.config({
        plugin = {
            hyprbars = {
                bar_height      = 26,
                bar_text_size   = 11,
                on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
            },
        },
    })

    -- Buttons are added right to left: close, maximize, minimize
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(ff5f57)", fg_color = "rgb(1e1e1e)", size = 14, icon = "✕",
                                  action = "hyprctl dispatch 'hl.dsp.window.close()'",
    })
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(28c840)", fg_color = "rgb(1e1e1e)", size = 14, icon = "□",
                                  action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
    })
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(febc2e)", fg_color = "rgb(1e1e1e)", size = 14, icon = "–",
                                  action = [[hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:special", follow = false })']],
    })

    -- No bar on tiled windows; bar appears when a window floats
    hl.window_rule({ match = { float = false }, ["hyprbars:no_bar"] = true })
    end
