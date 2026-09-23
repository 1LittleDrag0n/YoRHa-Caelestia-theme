#!/usr/bin/env fish
# Audio-reactive window effects. Each one is on while its flag file exists.
# Toggle with: audio-fx-toggle.fish glass | border

set fxdir ~/.config/caelestia/audio-fx
mkdir -p $fxdir

# --- glass effect (hyprglass) ---
set base_refr 0.3        # edge bending when quiet (same as glass.lua)
set base_chroma 0.15     # RGB split when quiet (same as glass.lua)
set max_refr 1.0         # edge bending at full volume
set max_chroma 0.95       # RGB split at full volume

# --- border effect ---
set base_color 8f7c4ae6  # normal YoRHa gold border
set palette 8f7c4ae6 8b5a3ae6 6b5a2ee6 7a6a3ae6 5e6a5ae6   # similar-brightness glitch colours
set base_round 15        # normal corner rounding (Caelestia default)
set glitch_round 4       # corners on loud hits
set glitch_at 0.45       # loudness (0-1) where colour/corner glitches start

set smooth 0.6           # 0 = twitchy, 0.9 = very smooth
set level 0
set angle 0
set last ""
set glass_was 0
set border_was 0

cava -p ~/.config/cava/glitch.conf | while read -l line
set vals (string split ';' -- $line | string match -r '^[0-9]+$')
test (count $vals) -eq 0; and continue

set peak (math "max("(string join , $vals)")/100")
set level (math "$smooth*$level + (1-$smooth)*$peak")
set cmd ""

# glass: bend + RGB split scale with loudness
if test -e $fxdir/glass
set refr (math "round(($base_refr + ($max_refr-$base_refr)*$level)*20)/20")
set chroma (math "round(($base_chroma + ($max_chroma-$base_chroma)*$level)*20)/20")
set cmd "$cmd if hl.plugin.hyprglass then hl.plugin.hyprglass.config({ refraction_strength = $refr, chromatic_aberration = $chroma }) end"
set glass_was 1
else if test $glass_was -eq 1
set cmd "$cmd if hl.plugin.hyprglass then hl.plugin.hyprglass.config({ refraction_strength = $base_refr, chromatic_aberration = $base_chroma }) end"
set glass_was 0
end

# border: gradient shears with loudness; colours and corners glitch on loud hits
if test -e $fxdir/border
set angle (math "($angle + round($level*6)*15) % 360")
set c1 $base_color
set c2 $base_color
set rnd $base_round
if test (math "$level > $glitch_at") -eq 1
set c1 $palette[(random 1 (count $palette))]
set c2 $palette[(random 1 (count $palette))]
set rnd $glitch_round
end
set cmd "$cmd hl.config({ general = { col = { active_border = { colors = { 'rgba($c1)', 'rgba($c2)' }, angle = $angle } } }, decoration = { rounding = $rnd } })"
set border_was 1
else if test $border_was -eq 1
set cmd "$cmd hl.config({ general = { col = { active_border = \"rgba($base_color)\" } }, decoration = { rounding = $base_round } })"
set border_was 0
end

if test -n "$cmd" -a "$cmd" != "$last"
hyprctl eval "$cmd" >/dev/null
set last $cmd
end
end
