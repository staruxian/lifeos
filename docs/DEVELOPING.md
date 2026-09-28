# Developing LifeOS

An Omarchy shell plugin (`staruxian.lifeos`) for tasks, habits, reading, countdowns
and people's birthdays, with a morning plan / evening shutdown rhythm. Published at
github.com/staruxian/lifeos and submitted to the Omarchy plugin marketplace.

## How it fits together

- `cli/lifeos/` — the `lifeos` CLI, Python 3 standard library only (`sqlite3`, `json`),
  so it runs on every Omarchy system with nothing to install. It **owns the data and
  computes everything**: streaks, heatmaps, reading pace, countdowns, alerts, the
  weekly score, insights. After every command it writes a snapshot to
  `~/.local/state/lifeos/state.json`.
- The QML at the repo root (`BarWidget.qml`, `Panel.qml`, `QuickAdd.qml`,
  `components/`, `pages/`, `views/`) only lays the snapshot out and calls the CLI.
  Don't compute in QML what the CLI can compute; add it to `cli/lifeos/state.py`.
- `BarWidget.qml` runs `python3 <plugin>/cli/lifeos/lifeos.py` (`$LIFEOS_BIN` overrides it).
  It queues commands, always passing `--json` first, and titles after `--`.
- `lifeos.py` is run as a script so Python never caches it in the plugin folder; the
  modules it imports cache under `~/.cache/lifeos/pycache` (`sys.pycache_prefix`).
- The CLI was ported from TypeScript/Bun in 1.4 and verified output-for-output against it.
  `cli/lifeos/jsmath.py` keeps the JavaScript semantics that matter: `Math.round` rounds
  halves up, JSON prints `1` not `1.0`, and `voice.py`'s 32-bit hash picks the same lines.
- `extras/LifeOS.lock.qml` is a Lock Screen Explorer design that reads the snapshot.

## Commands

```sh
python3 -m unittest discover -s cli/tests    # tests
python3 cli/lifeos/lifeos.py help            # the CLI
omarchy restart shell                        # REQUIRED after QML edits — the shell caches plugin QML
qs log -p /usr/share/omarchy/shell -t 400 | grep staruxian.lifeos   # QML warnings
```

Validate what would be published (only tracked and unignored files):
`T=$(mktemp -d); git ls-files -co --exclude-standard | tar -cf - -T - | tar -xf - -C $T; omarchy plugin validate $T`

## Rules

- **Never wipe or overwrite `~/.local/share/lifeos/lifeos.db`** — it is the user's real
  data. For demo data or screenshots: `sqlite3 <db> ".backup <copy>"` first, restore after.
  When testing the CLI, point `LIFEOS_DB`, `LIFEOS_STATE`, `LIFEOS_UNDO` at a scratch
  dir and `lifeos set notify off` there — `tick` sends real desktop notifications.
- Everything LifeOS writes is private (dirs 0700, files 0600; the CLI runs under
  `umask 077`). Keep it that way — the marketplace reviewed this.
- Schema changes: append a migration to `cli/lifeos/db.py`, never edit a shipped one.
  Add new tables to `TABLES` in `cli/lifeos/undo.py`.
- Standard library only in the CLI, and no install scripts or package-manager commands in
  the repo: the marketplace lists LifeOS for one-command installation because of it.
- Mutating CLI commands call `changing(ctx, label)` before the change so it can be undone.
- `manifest.json` stays at the repo root; the plugin id `staruxian.lifeos` is permanent.
  Bump `version` in `manifest.json` for each release.
- Strict mode and the day's rhythm are settings (`lifeos set`), read by the CLI.

## QML traps we have hit

- Don't name a property `data` — every Item has a read-only `data` (its children).
- Object literals in bindings need parentheses: `font.features: ({ "tnum": 1 })`.
- Inside `ShapePath` there is no `parent`; refer to the `Shape` by id.
- Signal handlers can't be attached through an alias (`input.onX:`); use `Connections`.
- Don't let a control assign to its own bound property (it breaks the binding): emit a
  signal and let the saved state flow back (see `components/Switch.qml`).
- Forms that edit live data take a frozen copy (`editTarget`), or the minute tick resets them.
- Width math must use a sized item — the `Panel` root has no width.
- There is one bar per monitor: once-only work (reminders, auto-opening, quick add) runs
  in the `leader` instance.

## Style

Colours come from the Omarchy theme via `components/Theme.qml`; shape, type and motion
are LifeOS's own (Apple-like: soft cards, capsules, short eased animations). Comments
explain *why*, sparingly. Keep user-facing text plain and friendly.
