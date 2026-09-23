-- Remove Caelestia binds that clash with Plasma keys
-- hl.unbind only matches the exact spelling, so try every spelling Caelestia has used
for _, k in ipairs({
    "ALT + TAB", "ALT + Tab", "SHIFT + ALT + TAB", "SHIFT + ALT + Tab",
    "SUPER + Page_Up", "SUPER + Page_up", "SUPER + Page_Down", "SUPER + Page_down",
    "SUPER + ALT + Left", "SUPER + ALT + Right", "SUPER + ALT + Up", "SUPER + ALT + Down",
    "SUPER + ALT + left", "SUPER + ALT + right", "SUPER + ALT + up", "SUPER + ALT + down",
}) do hl.unbind(k) end

-- Walk through windows (Alt+Tab / Meta+Tab), raising the window like KWin
local function walk(forward)
return function()
if forward then
    hl.dispatch(hl.dsp.window.cycle_next())
    else
        hl.dispatch(hl.dsp.window.cycle_next({ next = false }))
        end
        hl.dispatch(hl.dsp.window.bring_to_top())
        end
        end
        hl.bind("ALT + TAB", walk(true))
        hl.bind("SUPER + TAB", walk(true))
        hl.bind("SHIFT + ALT + TAB", walk(false))
        hl.bind("SUPER + SHIFT + TAB", walk(false))

        -- Maximize / restore (Meta+PgUp, Meta+Backspace)
        hl.bind("SUPER + Page_Up", hl.dsp.window.fullscreen({ mode = "maximized" }))
        hl.bind("SUPER + BackSpace", hl.dsp.window.fullscreen({ mode = "maximized" }))

        -- "Minimize" (Meta+PgDown): hides the window in the special workspace; Super+S shows it again
        hl.bind("SUPER + Page_Down", hl.dsp.window.move({ workspace = "special:special", follow = false }))

        -- Switch window focus (Meta+Alt+arrows)
        hl.bind("SUPER + ALT + left", hl.dsp.focus({ direction = "left" }))
        hl.bind("SUPER + ALT + right", hl.dsp.focus({ direction = "right" }))
        hl.bind("SUPER + ALT + up", hl.dsp.focus({ direction = "up" }))
        hl.bind("SUPER + ALT + down", hl.dsp.focus({ direction = "down" }))

        -- Desktops 1-4 (Meta+F1..F4, alongside Ctrl+F1..F4)
        for i = 1, 4 do
            hl.bind("SUPER + F" .. i, hl.dsp.focus({ workspace = tostring(i) }))
            end

            -- Launcher (Alt+F1), Kill window (Meta+Ctrl+Esc), Tiles (Meta+T also toggles tile/float)
            hl.bind("ALT + F1", hl.dsp.global("caelestia:launcher"))
            hl.bind("SUPER + CTRL + Escape", hl.dsp.exec_cmd("hyprctl kill"))
            hl.bind("SUPER + T", hl.dsp.window.float())

            -- Volume by 1% (Shift+Volume keys)
            hl.bind("SHIFT + XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 1%+"), { locked = true, repeating = true })
            hl.bind("SHIFT + XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-"), { locked = true, repeating = true })
            hl.bind("SUPER + XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
