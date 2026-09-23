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
