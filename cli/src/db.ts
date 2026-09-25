import { Database } from "bun:sqlite"
import { mkdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { homedir } from "node:os"

const home = homedir()

export const paths = {
  db: process.env.LIFEOS_DB ?? join(process.env.XDG_DATA_HOME ?? join(home, ".local/share"), "lifeos/lifeos.db"),
  state: process.env.LIFEOS_STATE ?? join(process.env.XDG_STATE_HOME ?? join(home, ".local/state"), "lifeos/state.json"),
}

// Each entry moves the schema one version forward. Never edit a shipped
// migration; append a new one.
const migrations: string[] = [
  `
  CREATE TABLE tasks (
    id         INTEGER PRIMARY KEY,
    title      TEXT NOT NULL,
    due        TEXT,
    done_on    TEXT,
    created_on TEXT NOT NULL
  );

  -- kind: check = did it or not, count = reach a target, avoid = stay clean.
  -- days: scheduled weekdays as a bitmask, bit 0 = Monday.
  CREATE TABLE habits (
    id         INTEGER PRIMARY KEY,
    name       TEXT NOT NULL,
    kind       TEXT NOT NULL CHECK (kind IN ('check', 'count', 'avoid')),
    target     INTEGER NOT NULL DEFAULT 1,
    unit       TEXT NOT NULL DEFAULT '',
    days       INTEGER NOT NULL DEFAULT 127,
    position   INTEGER NOT NULL DEFAULT 0,
    created_on TEXT NOT NULL
  );

  -- check: value 1 = done. count: value = how many. avoid: value 1 = slipped.
  CREATE TABLE habit_logs (
    habit_id INTEGER NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    day      TEXT NOT NULL,
    value    INTEGER NOT NULL,
    PRIMARY KEY (habit_id, day)
  );

  CREATE TABLE books (
    id          INTEGER PRIMARY KEY,
    title       TEXT NOT NULL,
    total_pages INTEGER NOT NULL CHECK (total_pages > 0),
    created_on  TEXT NOT NULL,
    finished_on TEXT
  );

  CREATE TABLE reading_logs (
    book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    day     TEXT NOT NULL,
    pages   INTEGER NOT NULL,
    PRIMARY KEY (book_id, day)
  );

  CREATE TABLE events (
    id         INTEGER PRIMARY KEY,
    title      TEXT NOT NULL,
    day        TEXT NOT NULL,
    emoji      TEXT NOT NULL DEFAULT '',
    created_on TEXT NOT NULL
  );
  `,
]

export function openDb(path = paths.db): Database {
  if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true })
  const db = new Database(path, { create: true, strict: true })
  db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 2000;")
  migrate(db)
  return db
}

function migrate(db: Database) {
  const row = db.query("PRAGMA user_version").get() as { user_version: number }
  for (let version = row.user_version; version < migrations.length; version++) {
    db.transaction(() => {
      db.exec(migrations[version]!)
      db.exec(`PRAGMA user_version = ${version + 1}`)
    })()
  }
}
