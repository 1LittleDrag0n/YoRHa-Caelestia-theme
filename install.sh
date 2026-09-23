#!/usr/bin/env bash
# YoRHa Hyprland setup installer.
# Assumes Hyprland and the Caelestia shell are already installed and working.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.config/yorha-backup-$STAMP"

say()  { printf '\n\033[1;33m==>\033[0m %s\n' "$*"; }
ok()   { printf '    \033[1;32m*\033[0m %s\n' "$*"; }
warn() { printf '    \033[1;31m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31mABORT:\033[0m %s\n\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

ASSUME_YES=0
NO_PLUGINS=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes)     ASSUME_YES=1 ;;
        --no-plugins) NO_PLUGINS=1 ;;
        -h|--help)
            cat <<EOF
usage: ./install.sh [-y] [--no-plugins]

  -y, --yes      don't ask for confirmation
  --no-plugins   skip the Hyprland plugins (title bars, glass, wobble, overviews)

Existing config is copied to ~/.config/yorha-backup-<timestamp> before anything
is overwritten.
EOF
            exit 0 ;;
        *) die "unknown option: $arg" ;;
    esac
done

confirm() {
    [ "$ASSUME_YES" = 1 ] && return 0
    read -r -p "    $1 [y/N] " reply
    [[ "$reply" =~ ^[Yy] ]]
}

# ---------------------------------------------------------------- 1. checks
say "Checking what you have"

[ -f /etc/arch-release ] || warn "not an Arch-based system: package installation will probably fail"

for c in hyprctl hyprpm git make; do
    have "$c" || die "$c not found. Install Hyprland first."
done
have qs || die "quickshell (qs) not found. Install the Caelestia shell first."
[ -d "$HOME/.config/hypr" ] || die "~/.config/hypr missing. Install the Caelestia dots first."

ok "Hyprland $(hyprctl version 2>/dev/null | head -1 | cut -d, -f1 | sed 's/^Hyprland, built from branch.*//;s/^/ /' || echo '')"
ok "quickshell and the Caelestia config are present"

# ---------------------------------------------------------- 2. dependencies
say "Packages this setup needs"

PKGS=(lua cava fuzzel kdeconnect jq ttf-jetbrains-mono-nerd)
MISSING=()
for p in "${PKGS[@]}"; do
    pacman -Qq "$p" >/dev/null 2>&1 || MISSING+=("$p")
done

if [ ${#MISSING[@]} -eq 0 ]; then
    ok "all present"
else
    warn "missing: ${MISSING[*]}"
    if confirm "Install them now?"; then
        if have paru;  then paru  -S --needed "${MISSING[@]}"
        elif have yay; then yay   -S --needed "${MISSING[@]}"
        else sudo pacman -S --needed "${MISSING[@]}"
        fi
    else
        warn "skipping; parts of the setup will not work"
    fi
fi

# --------------------------------------------------------------- 3. backup
say "Backing up your current config to $BACKUP"
mkdir -p "$BACKUP"
for d in caelestia quickshell cava; do
    [ -e "$HOME/.config/$d" ] && cp -r "$HOME/.config/$d" "$BACKUP/" && ok "saved $d"
done
[ -d "$HOME/.local/bin" ] && mkdir -p "$BACKUP/local-bin" && cp "$HOME"/.local/bin/*.fish "$BACKUP/local-bin/" 2>/dev/null || true

# ----------------------------------------------------------------- 4. files
say "Installing the config"

mkdir -p "$HOME/.config" "$HOME/.local/bin"
cp -r "$REPO/config/caelestia"  "$HOME/.config/"                   && ok "caelestia config (hypr-user.lua and friends)"
cp -r "$REPO/config/quickshell" "$HOME/.config/"                   && ok "desktop widget, dock and hotkey list"
[ -d "$REPO/config/cava" ] && cp -r "$REPO/config/cava" "$HOME/.config/" && ok "cava profile for the audio effects"

for f in "$REPO"/local-bin/*; do
    [ -e "$f" ] || continue
    install -Dm755 "$f" "$HOME/.local/bin/$(basename "$f")"
done
ok "scripts in ~/.local/bin"

# Per-machine state that should not be shared: start fresh if absent.
[ -f "$HOME/.config/caelestia/yorha-dock-pins.json" ] || echo '[]' > "$HOME/.config/caelestia/yorha-dock-pins.json"

# ---------------------------------------------------------------- 5. scheme
say "Installing the YoRHa colour scheme"

SCHEME_SRC="$REPO/config/caelestia/schemes/yorha/dark.txt"
if [ -f "$SCHEME_SRC" ]; then
    CAEL_PKG="$(python3 -c 'import caelestia, os; print(os.path.dirname(caelestia.__file__))' 2>/dev/null || true)"
    if [ -n "$CAEL_PKG" ] && [ -d "$CAEL_PKG/data/schemes" ]; then
        sudo mkdir -p "$CAEL_PKG/data/schemes/yorha/default"
        sudo cp "$SCHEME_SRC" "$CAEL_PKG/data/schemes/yorha/default/dark.txt"
        ok "scheme installed into $CAEL_PKG"
        warn "a caelestia update overwrites it; re-run this script if the scheme disappears"
    else
        warn "couldn't find the caelestia python package; scheme left in ~/.config/caelestia/schemes only"
    fi
fi

# --------------------------------------------------------------- 6. plugins
if [ "$NO_PLUGINS" = 0 ]; then
    say "Hyprland plugins"

    add_repo() {   # add_repo <url> <plugin-name>
        if hyprpm list 2>/dev/null | grep -q "$2"; then
            ok "$2 already known to hyprpm"
        else
            hyprpm add "$1" || warn "could not add $1"
        fi
    }

    hyprpm update || warn "hyprpm update failed; plugins may not build"

    add_repo https://github.com/1LittleDrag0n/hyprland-plugins hyprbars
    add_repo https://github.com/1LittleDrag0n/hyprglass        hyprglass
    add_repo https://github.com/1LittleDrag0n/hyprwobbly       hyprwobbly
    add_repo https://github.com/sandwichfarm/hyprexpo          hyprexpo
    add_repo https://github.com/gfhdhytghd/hymission           hymission

    for p in hyprbars hyprglass hyprwobbly hyprexpo hymission; do
        hyprpm enable "$p" 2>/dev/null && ok "enabled $p" || warn "could not enable $p"
    done

    hyprpm reload -n || true
else
    say "Skipping plugins (--no-plugins)"
fi

# ---------------------------------------------------------------- 7. finish
say "Starting it up"

if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    hyprctl reload >/dev/null && ok "Hyprland config reloaded"
    hyprctl configerrors | grep -q . && warn "config errors above, check them" || true
    pkill -f 'qs -c yorha-desk' 2>/dev/null || true
    pkill -f 'qs -c yorha-dock' 2>/dev/null || true
    hyprctl dispatch 'hl.dsp.exec_cmd("qs -c yorha-desk -d")' >/dev/null
    hyprctl dispatch 'hl.dsp.exec_cmd("qs -c yorha-dock -d")' >/dev/null
    ok "desktop widget and dock started"
else
    warn "not running inside Hyprland: log into your Hyprland session to see the result"
fi

cat <<EOF

Done.

  Hotkeys:      Super+/            (or the HOTKEYS button on the desktop)
  Dock:         click the line at the bottom of the screen
  Overviews:    Super+G grid, Super+Shift+G all desktops
  Effects:      Super+Alt+C CRT, Super+Alt+G audio glass, Super+Alt+B audio border

  Your previous config: $BACKUP
  Settings to review:   ~/.config/caelestia/hypr-user.lua
                        ~/.config/caelestia/hypr-vars.lua   (terminal, file manager, touchpad)

EOF
