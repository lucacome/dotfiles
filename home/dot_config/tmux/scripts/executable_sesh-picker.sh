#!/usr/bin/env sh

result="$(
  sesh list --icons | fzf-tmux -p 80%,70% \
    --print-query \
    --exact \
    --no-sort --ansi --border-label ' sesh ' --prompt '⚡  ' \
    --header '  ^a all ^t tmux ^g configs ^x zoxide ^d tmux kill ^f find' \
    --bind 'tab:down,btab:up' \
    --bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)' \
    --bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)' \
    --bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)' \
    --bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)' \
    --bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' \
    --bind 'ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(⚡  )+reload(sesh list --icons)' \
    --preview-window 'right:55%' \
    --preview 'sesh preview {}'
)"

[ -z "$result" ] && exit 0

query="$(printf '%s\n' "$result" | sed -n '1p')"
selection="$(printf '%s\n' "$result" | sed -n '2p')"

if [ -n "$selection" ]; then
  # Existing sesh item selected.
  target="$(printf '%s\n' "$selection" | sed 's/^[^ ]* *//')"
else
  # No selection; use typed query.
  target="$query"

  [ -z "$target" ] && exit 0

  # tmux session names cannot contain ':'.
  target="$(printf '%s' "$target" | tr ':' '_')"

  # Create the tmux session first so sesh can connect to it.
  tmux has-session -t "=$target" 2>/dev/null || tmux new-session -d -s "$target"
fi

exec sesh connect "$target"
