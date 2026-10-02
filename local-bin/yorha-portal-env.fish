#!/usr/bin/env fish
# The portal chooses its backends at startup, before Hyprland finishes setting
# up the session, so it picks wrong. Redo it once the session is settled.
sleep 10
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE
systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE
systemctl --user reset-failed xdg-desktop-portal.service
systemctl --user restart xdg-desktop-portal.service
sleep 3
pkill -f kdeconnectd
sleep 1
setsid /usr/bin/kdeconnectd >/dev/null 2>&1 &
