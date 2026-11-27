#!/bin/sh
# Route a direction key to Rex panes while Rex is frontmost, and to AeroSpace
# windows everywhere else.
#
#   rex-pane.sh focus left   -> pane.focus in Rex, else aerospace focus left
#   rex-pane.sh move  left   -> pane.move  in Rex, else aerospace move left
#   rex-pane.sh swap  left   -> pane.move  in Rex, else aerospace swap left
#
# Rex has no directional pane swap yet (only `rex swap BLOCK OTHER`), so swap
# moves panes inside Rex and swaps whole windows everywhere else.
#
# When Rex has nothing to do in that direction (pane.move at the edge of a
# window, for instance) the key falls through to AeroSpace, so window
# movement still works from a lone pane.
#
# Bound in ~/.config/aerospace/aerospace.toml:
#   alt-h       = 'exec-and-forget ~/bin/rex-pane.sh focus left'
#   alt-shift-h = 'exec-and-forget ~/bin/rex-pane.sh swap left'
#
# The Rex client label defaults to "studio"; override with REX_CLIENT.

action=${1:?usage: rex-pane.sh focus|move|swap left|down|up|right}
dir=${2:?usage: rex-pane.sh focus|move|swap left|down|up|right}

case $action in
  focus | move | swap) ;;
  *)
    echo "rex-pane.sh: unknown action \"$action\"" >&2
    exit 2
    ;;
esac

aerospace=$(command -v aerospace) || aerospace=/opt/homebrew/bin/aerospace
[ -x "$aerospace" ] || {
  echo "rex-pane.sh: aerospace not found" >&2
  exit 1
}
# AeroSpace's exec environment has no ~/.local/bin in PATH.
rex=$(command -v rex) || rex="$HOME/.local/bin/rex"
[ -x "$rex" ] || rex=""

if [ -n "$rex" ] && [ "$("$aerospace" list-windows --focused --format '%{app-name}')" = "Rex" ]; then
  rex_action=$action
  # Flip this to $action when Rex gains a directional pane swap.
  [ "$action" = swap ] && rex_action=move
  if "$rex" -C "${REX_CLIENT:-studio}" do "pane.$rex_action" "direction=$dir" >/dev/null 2>&1; then
    exit 0
  fi
fi

exec "$aerospace" "$action" "$dir"
