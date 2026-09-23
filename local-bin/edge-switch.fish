#!/usr/bin/env fish
   # Top-left hot corner -> overview; left/right edges -> switch desktop
   set dwell 0.4
   set corner_dwell 0.2
   set armed 1

   while true
       sleep 0.15
       set pos (hyprctl cursorpos | string split ', ')
       set x $pos[1]
       set y $pos[2]
       set w (hyprctl monitors -j | jq '.[] | select(.focused) | (.width / .scale | floor)')
       test -z "$x" -o -z "$y" -o -z "$w"; and continue

       set zone none
       if test $x -le 2 -a $y -le 2
           set zone corner
       else if test $x -le 2
           set zone left
       else if test $x -ge (math $w - 2)
           set zone right
       end

       if test $zone = none
           set armed 1
           continue
       end
       test $armed -eq 0; and continue

       if test $zone = corner
           sleep $corner_dwell
       else
           sleep $dwell
       end

       set pos2 (hyprctl cursorpos | string split ', ')
       set x2 $pos2[1]
       set y2 $pos2[2]

       switch $zone
           case corner
               if test $x2 -le 2 -a $y2 -le 2
                    hyprctl eval 'hl.plugin.hymission.toggle("onlycurrentworkspace")' >/dev/null
                   set armed 0
               end
           case left
               if test $x2 -le 2 -a $y2 -gt 2
                   hyprctl dispatch 'hl.dsp.focus({ workspace = "-1" })' >/dev/null
                   set armed 0
               end
           case right
               if test $x2 -ge (math $w - 2)
                   hyprctl dispatch 'hl.dsp.focus({ workspace = "+1" })' >/dev/null
                   set armed 0
               end
       end
   end
