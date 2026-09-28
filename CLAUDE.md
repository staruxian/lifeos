# LifeOS

An Omarchy shell plugin (`staruxian.lifeos`) for tasks, habits, reading, countdowns
and people's birthdays, with a morning plan / evening shutdown rhythm. Published at
github.com/staruxian/lifeos and submitted to the Omarchy plugin marketplace.

## How it fits together

- `cli/` — the `lifeos` CLI (Bun + TypeScript + `bun:sqlite`). It **owns the data and
  computes everything**: streaks, heatmaps, reading pace, countdowns, alerts, the
  weekly score, insights. After every command it writes a snapshot to
  `~/.local/state/lifeos/state.json`.
- The QML at the repo root (`BarWidget.qml`, `Panel.qml`, `QuickAdd.qml`,
  `components/`, `pages/`, `views/`) only lays the snapshot out and calls the CLI.
  Don't compute in QML what the CLI can compute; add it to `cli/src/state.ts`.
- `BarWidget.qml` finds the CLI in order: `$LIFEOS_BIN`, `~/.local/bin/lifeos`
  (built by `install.sh`), then `bun cli/src/index.ts`. It queues commands, always
  passing `--json` first, and titles after `--`.
- `extras/LifeOS.lock.qml` is a Lock Screen Explorer design that reads the snapshot.

## Commands

```sh
cd cli && bun test              # tests (bun:test)
cd cli && bun run typecheck     # tsc --noEmit
./install.sh                    # rebuild ~/.local/bin/lifeos, link the plugin
omarchy restart shell           # REQUIRED after QML edits — the shell caches plugin QML
qs log -p /usr/share/omarchy/shell -t 400 | grep staruxian.lifeos   # QML warnings
```

Validate what would be published (the local tree has `cli/node_modules` symlinks the
validator rejects):
`T=$(mktemp -d); git ls-files -co --exclude-standard | tar -cf - -T - | tar -xf - -C $T; omarchy plugin validate $T`

## Rules

- **Never wipe or overwrite `~/.local/share/lifeos/lifeos.db`** — it is the user's real
  data. For demo data or screenshots: `sqlite3 <db> ".backup <copy>"` first, restore after.
  When testing the CLI, point `LIFEOS_DB`, `LIFEOS_STATE`, `LIFEOS_UNDO` at a scratch
  dir and `lifeos set notify off` there — `tick` sends real desktop notifications.
- Everything LifeOS writes is private (dirs 0700, files 0600; the CLI runs under
  `umask 077`). Keep it that way — the marketplace reviewed this.
- Schema changes: append a migration to `cli/src/db.ts`, never edit a shipped one.
  Add new tables to `TABLES` in `cli/src/undo.ts`.
- Mutating CLI commands call `changing(ctx, label)` before the change so it can be undone.
- `manifest.json` stays at the repo root; the plugin id `staruxian.lifeos` is permanent.
  Bump `version` in `manifest.json` and `cli/package.json` for each release.
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
