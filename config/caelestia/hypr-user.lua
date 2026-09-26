
-- KDE Connect daemon (Plasma starts this itself; Hyprland does not)
hl.on("hyprland.start", function()
    hl.dispatch(hl.dsp.exec_cmd("/usr/bin/kdeconnectd"))
end)

-- Touchpad pointer speed (-1.0 to 1.0)
hl.device({
    name          = "elan050a:01-04f3:3158-touchpad",
    sensitivity   = 0.2,
    accel_profile = "adaptive",
})

-- Plasma-style keybinds
require("kde-keys")

-- Render on Intel iGPU; NVIDIA only for outputs wired to it
hl.env("AQ_DRM_DEVICES", "/dev/dri/intel-igpu:/dev/dri/nvidia-dgpu")

-- Floating by default; Super+F / Super+T tiles a window
hl.window_rule({ match = { class = ".*" }, float = true })

-- Raise floating windows when they get focus (KDE behaviour)
hl.on("window.active", function(w)
    if w and w.floating then
        hl.dispatch(hl.dsp.window.bring_to_top())
    end
end)

-- Focus changes on click, not hover
hl.config({ input = { follow_mouse = 2 } })

-- Title bars (hyprbars plugin)
hl.on("hyprland.start", function()
    hl.dispatch(hl.dsp.exec_cmd("hyprpm reload -n && hyprctl reload"))
end)
require("titlebars")
require("glass")

-- Overview (hyprexpo): 2x2 grid of desktops, Super+G like KDE Grid View
if hl.plugin and hl.plugin.hyprexpo then
    hl.config({ plugin = { hyprexpo = { columns = 2, rows = 2, gaps_in = 8, gaps_out = 20, workspace_method = "first 1", skip_empty = 0 } } })
    hl.bind("SUPER + G", function() hl.plugin.hyprexpo.expo("toggle") end)
end

-- Window overview (hymission), KDE Overview style
if hl.plugin and hl.plugin.hymission then
    hl.config({ plugin = { hymission = { layout_engine = "natural", workspace_strip_anchor = "top", toggle_switch_mode = 0, only_active_workspace = 1 } } })
end

-- KRunner on Alt+Space (Plasma default), floating at the top
hl.bind("ALT + space", hl.dsp.exec_cmd("krunner"))
hl.window_rule({ match = { class = "org.kde.krunner" }, float = true, move = "(monitor_w*0.5-window_w*0.5) (monitor_h*0.08)", tag = "+hyprglass_disabled" })

-- YoRHa CRT screen shader (Super+Alt+C toggles; off for colour grading)
local crt_path = os.getenv("HOME") .. "/.config/caelestia/crt.glsl"
local crt_on = true
hl.config({ decoration = { screen_shader = crt_path } })
hl.bind("SUPER + ALT + C", function()
    crt_on = not crt_on
    hl.config({ decoration = { screen_shader = crt_on and crt_path or "" } })
end)

-- YoRHa desktop app widget
hl.on("hyprland.start", function()
    hl.dispatch(hl.dsp.exec_cmd("qs -c yorha-desk -d"))
end)

-- Floating by default; Super+F / Super+T tiles a window

-- Default size for new floating windows: 64% x 80%, centred (~18% gap left/right)
hl.window_rule({
    match = {
        class = "negative:(org.kde.krunner|org.quickshell|feh|imv|swappy|yad|zenity|wev|blueman-manager|file-roller|org.gnome.FileRoller|nwg-look|org.pulseaudio.pavucontrol|com.saivert.pwvucontrol|steam|polkit-gnome-authentication-agent-1)",
        title = "negative:(|Picture(-| )in(-| )[Pp]icture|File (Operation|Upload)( Progress)?|.* Properties|Rename .*|(Select|Open)( a)? (File|Folder)(s)?.*|Save As.*|(Open|Save) File.*)",
    },
    size = "(monitor_w*0.65) (monitor_h*0.92)",
    center = true,
})

-- Edge desktop switching + hot corner
hl.on("hyprland.start", function()
    hl.dispatch(hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/edge-switch.fish"))
end)

-- Extra title bar buttons (pin, menu, hide from screen share)
require("titlebar-extra")

-- Audio FX toggles: Super+Alt+G glass, Super+Alt+B border
hl.bind("SUPER + ALT + G", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/audio-fx-toggle.fish glass"))
hl.bind("SUPER + ALT + B", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/audio-fx-toggle.fish border"))

-- Audio-reactive window effects
hl.on("hyprland.start", function()
    hl.dispatch(hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/audio-glitch.fish"))
end)

-- Hotkey list popup
hl.bind("SUPER + slash", hl.dsp.exec_cmd("qs -c yorha-desk ipc call hotkeys toggle"))

-- Frosted glass behind the dock
hl.layer_rule({ match = { namespace = "yorha-dock" }, blur = true, ignore_alpha = 0.1 })


-- Hyprland plugins built locally
hl.on("hyprland.start", function()
end)

-- YoRHa dock
hl.on("hyprland.start", function()
    hl.dispatch(hl.dsp.exec_cmd("sh -c 'qs -c yorha-dock >/tmp/yorha-dock.log 2>&1'"))
end)

-- Wobbly windows
hl.config({ plugin = { hyprwobbly = {
    glass_return_ms = 600,
    grab_radius = 0.22,
    strength = 0.8,
    stiffness = 9.0,
    friction = 3.9,
    max_offset = 45.0,
} } })

-- Wobbly windows
hl.config({ plugin = { hyprwobbly = { glass_return_ms = 120 } } })

-- Show / hide the dock
hl.bind("SUPER + ALT + D", hl.dsp.exec_cmd("qs -c yorha-dock ipc call dock toggle"))

