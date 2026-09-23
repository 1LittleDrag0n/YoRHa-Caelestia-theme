#!/usr/bin/env fish
# Window operations menu for the hyprbars menu button
set addr (hyprctl activewindow -j | jq -r '.address')
test -z "$addr" -o "$addr" = null; and exit

set choice (printf '%s\n' \
    '󰐃  Pin / unpin (on top, all desktops)' \
    '󰕰  Tile / float' \
    '󰊓  Fullscreen' \
    '󰈉  Hide from screen share (toggle)' \
    '󰘕  Minimize' \
    '1  Move to desktop 1' \
    '2  Move to desktop 2' \
    '3  Move to desktop 3' \
    '4  Move to desktop 4' \
    '󰖭  Close' | fuzzel --dmenu --prompt 'window ▸ ')

set w "address:$addr"
switch "$choice"
    case '*Pin*'
        hyprctl dispatch "hl.dsp.window.pin({ window = \"$w\" })"
    case '*Tile*'
        hyprctl dispatch "hl.dsp.window.float({ action = \"toggle\", window = \"$w\" })"
    case '*Fullscreen*'
        hyprctl dispatch "hl.dsp.focus({ window = \"$w\" })"
        hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen" })'
    case '*screen share*'
        hyprctl dispatch "hl.dsp.window.tag({ tag = \"private\", window = \"$w\" })"
    case '*Minimize*'
        hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:special\", follow = false, window = \"$w\" })"
    case '1 *' '2 *' '3 *' '4 *'
        set n (string sub -l 1 -- $choice)
        hyprctl dispatch "hl.dsp.window.move({ workspace = \"$n\", follow = false, window = \"$w\" })"
    case '*Close*'
        hyprctl dispatch "hl.dsp.window.close({ window = \"$w\" })"
end
