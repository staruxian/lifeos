#!/usr/bin/env bash
# Optional extras for LifeOS: a compiled `lifeos` command for your terminal
# (and a slightly faster panel), linking a local checkout into the shell, and
# a Lock Screen Explorer design. The plugin itself works without this as
# long as Bun is installed.
#
# It never replaces a file it did not put there: everything it installs is
# recorded (with a checksum, or a link's target) in
# ~/.local/share/lifeos/installed, and uninstall.sh removes only entries that
# are still exactly as installed. Safe to re-run; your data is not touched.
set -euo pipefail
umask 077

here="$(cd "$(dirname "$0")" && pwd)"
plugin_id="staruxian.lifeos"
plugins_dir="$HOME/.config/omarchy/plugins"
bin_dir="$HOME/.local/bin"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/lifeos"
manifest="$data_dir/installed"

bun="$(command -v bun || true)"
[[ -z "$bun" && -x "$HOME/.bun/bin/bun" ]] && bun="$HOME/.bun/bin/bun"
if [[ -z "$bun" ]]; then
  echo "LifeOS needs Bun. Install it with: omarchy pkg add bun" >&2
  exit 1
fi

mkdir -p "$data_dir"
chmod 700 "$data_dir"
touch "$manifest"
chmod 600 "$manifest"

sum() { sha256sum "$1" | cut -d' ' -f1; }

# The checksum recorded for a path, if this installer put it there.
recorded() { awk -F'\t' -v k="$1" -v p="$2" '$1 == k && $2 == p { print $3 }' "$manifest"; }

record() {
  local kind="$1" path="$2" value="$3" tmp
  tmp="$(mktemp "$manifest.XXXXXX")"
  awk -F'\t' -v k="$kind" -v p="$path" '!($1 == k && $2 == p)' "$manifest" > "$tmp"
  printf '%s\t%s\t%s\n' "$kind" "$path" "$value" >> "$tmp"
  mv "$tmp" "$manifest"
}

# Copies $1 to $2 unless $2 exists and is not the copy made last time.
place() {
  local src="$1" dest="$2" mode="$3" before
  if [[ -e "$dest" || -L "$dest" ]]; then
    before="$(recorded file "$dest")"
    if [[ -L "$dest" || -z "$before" || "$(sum "$dest")" != "$before" ]]; then
      echo "  skipped $dest — something else is there (or it was changed); left alone" >&2
      return 1
    fi
  fi
  mkdir -p "$(dirname "$dest")"
  install -m "$mode" "$src" "$dest"
  record file "$dest" "$(sum "$dest")"
}

echo "→ building the lifeos command"
(cd "$here/cli" && "$bun" test &>/dev/null && "$bun" build src/index.ts --compile --outfile dist/lifeos &>/dev/null)
if place "$here/cli/dist/lifeos" "$bin_dir/lifeos" 755; then
  lifeos="$bin_dir/lifeos"
else
  lifeos="$here/cli/dist/lifeos"
  echo "  the panel will run LifeOS from source with Bun instead" >&2
fi

# A checkout elsewhere (for hacking on it) gets linked in; a copy installed
# with `omarchy plugin add` already lives in the plugins folder.
link="$plugins_dir/$plugin_id"
if [[ "$here" != "$link" ]]; then
  if [[ -L "$link" && "$(readlink "$link")" == "$here" ]]; then
    record link "$link" "$here"
  elif [[ -e "$link" || -L "$link" ]]; then
    echo "  $link already exists and is not this checkout — left alone" >&2
  else
    echo "→ linking $here into the shell"
    mkdir -p "$plugins_dir"
    ln -s "$here" "$link"
    record link "$link" "$here"
  fi
fi

"$lifeos" state >/dev/null

# With Lock Screen Explorer installed, offer the LifeOS lock design. It is
# only added to your designs; pick it yourself in the explorer.
if [[ -d "$plugins_dir/io.github.sirjul1337.lock-explorer" ]]; then
  if place "$here/extras/LifeOS.lock.qml" "$HOME/.config/omarchy/lock-designs/LifeOS.qml" 644; then
    echo "→ lock design added — choose it with: omarchy-shell lock explore (Custom → LifeOS)"
  fi
fi

if command -v omarchy-shell >/dev/null && omarchy-shell shell ping >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null
  omarchy plugin enable "$plugin_id" --section right >/dev/null 2>&1 || true
fi

echo "✓ Done. Try: lifeos help"
