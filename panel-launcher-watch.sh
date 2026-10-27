#!/usr/bin/env bash
set -u

CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
FILE="plasma-org.kde.plasma.desktop-appletsrc"
SYNC="$(dirname "$(readlink -f "$0")")/panel-launcher-sync.sh"

sleep 10
"$SYNC" || true

inotifywait -m -q -e close_write,moved_to --format '%f' "$CFG_DIR" |
while read -r f; do
  [ "$f" = "$FILE" ] || continue
  while read -r -t 2 _; do :; done
  "$SYNC" || true
done
