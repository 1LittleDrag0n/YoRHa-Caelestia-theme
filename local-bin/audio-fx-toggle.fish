#!/usr/bin/env fish
# Toggle an audio effect: audio-fx-toggle.fish glass|border
set f ~/.config/caelestia/audio-fx/$argv[1]
mkdir -p (dirname $f)
if test -e $f
    rm $f
    notify-send -a "Audio FX" "$argv[1] effect off"
else
    touch $f
    notify-send -a "Audio FX" "$argv[1] effect on"
end

# make sure the effect daemon is alive
pgrep -f audio-glitch.fish >/dev/null; or hyprctl dispatch "hl.dsp.exec_cmd(\"$HOME/.local/bin/audio-glitch.fish\")"
