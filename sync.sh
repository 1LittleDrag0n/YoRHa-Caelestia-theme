#!/usr/bin/env bash
# Copy the live config on this machine back into the repo, then check it for
# anything personal. Run this after you change something and want it published.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
say() { printf '\n\033[1;33m==>\033[0m %s\n' "$*"; }

say "Copying config out of ~/.config"
mkdir -p "$REPO/config" "$REPO/local-bin"

rsync -a --delete \
      --exclude 'yorha-dock-pos.json' \
      --exclude 'yorha-dock-pins.json' \
      --exclude '*.log' --exclude '*.cache' \
      "$HOME/.config/caelestia/" "$REPO/config/caelestia/"

rsync -a --delete "$HOME/.config/quickshell/" "$REPO/config/quickshell/"
[ -d "$HOME/.config/cava" ] && rsync -a --delete "$HOME/.config/cava/" "$REPO/config/cava/"

for f in "$HOME"/.local/bin/*.fish; do
    [ -e "$f" ] && cp "$f" "$REPO/local-bin/"
done

say "Privacy check"
python3 "$REPO/privacy-check.py" || {
    echo
    echo "Fix the above (or accept it) before committing."
    exit 1
}

say "Ready to commit"
cd "$REPO"
git status --short
cat <<EOF

  git add -A
  git commit -m "update config"
  git push

EOF
