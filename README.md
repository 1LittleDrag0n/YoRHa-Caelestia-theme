# YoRHa Hyprland setup

A NieR:Automata-flavoured Hyprland setup built on top of the
[Caelestia](https://github.com/caelestia-dots/shell) shell: KDE-style hotkeys,
floating windows with title bars, a liquid-glass effect, a macOS-style dock, a
desktop app widget, a searchable hotkey list, audio-reactive effects, a CRT
shader, and wobbly windows.

## Requirements

Hyprland 0.56.x and the Caelestia shell, already installed and working.
Arch-based system (the installer uses pacman/paru).

## Install

```sh
git clone https://github.com/1LittleDrag0n/YoRHa-Caelestia-theme ~/YoRHa-Caelestia-theme
cd ~/YoRHa-Caelestia-theme
./install.sh
```

It backs up your current config to `~/.config/yorha-backup-<timestamp>` first,
installs the missing packages, copies the config and scripts, adds the colour
scheme, and installs the Hyprland plugins through hyprpm. `./install.sh -y`
skips the prompts, `--no-plugins` leaves the plugins alone.

## What you get

| | |
|---|---|
| `Super+/` | searchable hotkey list, read from your live config |
| bottom line | click it for the dock; drag it to move it |
| `Super+G` / `Super+Shift+G` | desktop grid / all-desktops overview |
| `Super+Alt+C` | CRT shader |
| `Super+Alt+G` / `Super+Alt+B` | audio-reactive glass / border |
| title bars | pin, window menu, hide-from-screenshare on the left; close/max/min on the right |
| wobbly windows | grab point follows the cursor, the rest trails |

## Plugins

| plugin | what for |
|---|---|
| [hyprbars (fork)](https://github.com/1LittleDrag0n/hyprland-plugins) | title bars with extra buttons, rendered so window transformers apply |
| [hyprglass (fork)](https://github.com/1LittleDrag0n/hyprglass) | liquid glass, with a fade-in when it is re-enabled |
| [hyprwobbly](https://github.com/1LittleDrag0n/hyprwobbly) | wobbly windows |
| [hyprexpo](https://github.com/sandwichfarm/hyprexpo) | desktop grid |
| [hymission](https://github.com/gfhdhytghd/hymission) | window overview |

## Settings

- `config/caelestia/hypr-vars.lua` - terminal, file manager, touchpad, window opacity
- `config/caelestia/hypr-user.lua` - everything else: hotkeys, rules, autostart, effects
- `config/quickshell/yorha-dock/shell.qml` - dock: size, position, magnification, glass
- `config/quickshell/yorha-desk/shell.qml` - desktop widget: favourite apps, position

## Publishing changes

```sh
./sync.sh        # copy live config into the repo and run the privacy check
```

`./privacy-check.py` scans for tokens, emails, IPs, MACs, phone numbers,
coordinates and location settings, plus your own name, username, hostname and
home path taken from this machine. `--fix` rewrites your home path to `$HOME`.

## KDE Connect remote input

Remote input (phone as touchpad/keyboard) needs a `RemoteDesktop` portal backend,
which xdg-desktop-portal-hyprland does not implement yet:

```sh
paru -S hypr-kdeconnect-fix-git
```

No config needed - the portal auto-selects it, and it is D-Bus activated.
Do not add a portals.conf; pinning `default=` there changes routing for
screencast and screenshot too.
