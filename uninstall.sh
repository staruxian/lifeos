#!/usr/bin/env bash
# Remove the lifeos command and the local plugin link. Your data stays in
# ~/.local/share/lifeos unless you pass --purge.
set -euo pipefail

plugin_id="staruxian.lifeos"
link="$HOME/.config/omarchy/plugins/$plugin_id"

omarchy plugin disable "$plugin_id" >/dev/null 2>&1 || true
[[ -L "$link" ]] && rm "$link" && echo "→ removed plugin link"
[[ -f "$HOME/.local/bin/lifeos" ]] && rm "$HOME/.local/bin/lifeos" && echo "→ removed ~/.local/bin/lifeos"

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/lifeos" "${XDG_STATE_HOME:-$HOME/.local/state}/lifeos"
  echo "→ deleted your LifeOS data"
fi
echo "✓ LifeOS removed"
