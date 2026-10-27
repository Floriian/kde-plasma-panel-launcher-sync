#!/usr/bin/env bash
tól.
set -euo pipefail

WIDGET="${PANEL_SYNC_WIDGET:-org.kde.plasma.icontasks}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/panel-launcher-sync/last"
mkdir -p "$(dirname "$STATE")"

QDBUS="$(command -v qdbus6 || command -v qdbus || true)"
[ -n "$QDBUS" ] || { echo "qdbus/qdbus6 nem található" >&2; exit 1; }

eval_js() {
  "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"
}


dump="$(eval_js "
panels().forEach(function(p) {
  p.widgets('$WIDGET').forEach(function(w) {
    w.currentConfigGroup = ['General'];
    print(p.screen + '\t' + String(w.readConfig('launchers', [])) + '\n');
  });
});")"

mapfile -t raw <<< "$dump"
lines=()
for l in "${raw[@]}"; do
  if [ -n "$l" ]; then lines+=("$l"); fi
done
[ "${#lines[@]}" -ge 2 ] || exit 0

found=0
source=""
if [ -f "$STATE" ]; then
  last="$(cat "$STATE")"
  for line in "${lines[@]}"; do
    list="${line#*$'\t'}"
    if [ "$list" != "$last" ]; then source="$list"; found=1; break; fi
  done
else
  for line in "${lines[@]}"; do
    if [ "${line%%$'\t'*}" = "0" ]; then source="${line#*$'\t'}"; found=1; break; fi
  done
fi
[ "$found" -eq 1 ] || exit 0

escaped="$(printf '%s' "$source" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")"

reordered="$(eval_js "
var src = '$escaped';
var arr = src.length ? src.split(',') : [];
var touched = 0;
panels().forEach(function(p) {
  p.widgets('$WIDGET').forEach(function(w) {
    w.currentConfigGroup = ['General'];
    var cur = w.readConfig('launchers', []);
    cur = (typeof cur === 'string') ? (cur.length ? cur.split(',') : [])
                                    : Array.prototype.slice.call(cur);
    if (String(cur) === src || cur.length !== arr.length) return;
    if (cur.slice().sort().join(',') !== arr.slice().sort().join(',')) return;
    var keep = cur.filter(function(x, i) { return arr[i] === x; });
    w.writeConfig('launchers', keep);
    w.reloadConfig();
    touched++;
  });
});
print(touched);")"
if [ "${reordered:-0}" != "0" ]; then sleep 1; fi

eval_js "
var src = '$escaped';
var arr = src.length ? src.split(',') : [];
panels().forEach(function(p) {
  p.widgets('$WIDGET').forEach(function(w) {
    w.currentConfigGroup = ['General'];
    if (String(w.readConfig('launchers', [])) !== src) {
      w.writeConfig('launchers', arr);
      w.reloadConfig();
    }
  });
});" > /dev/null

printf '%s' "$source" > "$STATE"
