#!/usr/bin/env bash
# Optional extras for LifeOS: a compiled `lifeos` command for your terminal
# (and a slightly faster panel), plus linking a local checkout into the shell.
# The plugin itself works without this as long as Bun is installed.
# Safe to re-run: it rebuilds the binary and never touches your data.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
plugin_id="staruxian.lifeos"
plugins_dir="$HOME/.config/omarchy/plugins"
bin_dir="$HOME/.local/bin"

bun="$(command -v bun || true)"
[[ -z "$bun" && -x "$HOME/.bun/bin/bun" ]] && bun="$HOME/.bun/bin/bun"
if [[ -z "$bun" ]]; then
  echo "LifeOS needs Bun. Install it with: omarchy pkg add bun" >&2
  exit 1
fi

echo "→ building the lifeos command"
(cd "$here/cli" && "$bun" test &>/dev/null && "$bun" build src/index.ts --compile --outfile dist/lifeos &>/dev/null)
mkdir -p "$bin_dir"
install -m 755 "$here/cli/dist/lifeos" "$bin_dir/lifeos"

# A checkout elsewhere (for hacking on it) gets linked in; a copy installed
# with `omarchy plugin add` already lives in the plugins folder.
if [[ "$here" != "$plugins_dir/$plugin_id" ]]; then
  echo "→ linking $here into the shell"
  mkdir -p "$plugins_dir"
  if [[ -e "$plugins_dir/$plugin_id" && ! -L "$plugins_dir/$plugin_id" ]]; then
    echo "  $plugins_dir/$plugin_id already exists and is not a link — remove it first" >&2
    exit 1
  fi
  ln -sfn "$here" "$plugins_dir/$plugin_id"
fi

"$bin_dir/lifeos" state >/dev/null

if command -v omarchy-shell >/dev/null && omarchy-shell shell ping >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null
  omarchy plugin enable "$plugin_id" --section right >/dev/null 2>&1 || true
fi

echo "✓ Done. Try: lifeos help"
