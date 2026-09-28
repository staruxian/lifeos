#!/usr/bin/env bash
# Remove what install.sh added — only entries it recorded, and only while they
# are still exactly as it left them. Anything else at those paths is kept.
# Your data stays in ~/.local/share/lifeos unless you pass --purge.
set -euo pipefail

plugin_id="staruxian.lifeos"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/lifeos"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/lifeos"
manifest="$data_dir/installed"

omarchy plugin disable "$plugin_id" >/dev/null 2>&1 || true

if [[ -f "$manifest" ]]; then
  while IFS=$'\t' read -r kind path value; do
    [[ -n "$path" ]] || continue
    case "$kind" in
      file)
        if [[ -f "$path" && ! -L "$path" && "$(sha256sum "$path" | cut -d' ' -f1)" == "$value" ]]; then
          rm "$path" && echo "→ removed $path"
        elif [[ -e "$path" ]]; then
          echo "  kept $path — it changed since LifeOS installed it"
        fi ;;
      link)
        # Written by installers before 1.3.3, which could record a link the
        # user made. Never trusted: the link is left alone.
        [[ -e "$path" || -L "$path" ]] && echo "  kept $path — not known to be created by install.sh" ;;
      made-link)
        if [[ -L "$path" && "$(readlink "$path")" == "$value" ]]; then
          rm "$path" && echo "→ removed $path"
        elif [[ -e "$path" || -L "$path" ]]; then
          echo "  kept $path — it no longer points at the LifeOS checkout"
        fi ;;
    esac
  done < "$manifest"
  rm "$manifest"
else
  echo "Nothing recorded as installed by install.sh."
fi

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$data_dir" "$state_dir"
  echo "→ deleted your LifeOS data"
fi
echo "✓ LifeOS removed"
