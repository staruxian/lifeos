import type { Database } from "bun:sqlite"
import { existsSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"
import { paths, privateDir } from "./db"
import { LifeError } from "./store"

// One level of undo. Before a change, the whole database (it is small) is
// written beside the state file together with a label for the change; undo
// copies the tables back. Sent notifications are not part of it — undoing a
// check-off should not send the evening reminder twice.

const TABLES = ["tasks", "habits", "habit_logs", "books", "reading_logs", "events", "days", "settings", "people"]

export interface Change {
  label: string
  at: string
}

function metaPath(path: string) {
  return `${path}.json`
}

// Taken before a change and saved only once the change has succeeded, so a
// refused change never replaces the undo you might still want.
export function capture(db: Database): Uint8Array {
  return db.serialize()
}

export function saveSnapshot(bytes: Uint8Array, label: string, path = paths.undo) {
  privateDir(dirname(path))
  writeFileSync(path, bytes, { mode: 0o600 })
  writeFileSync(metaPath(path), JSON.stringify({ label, at: new Date().toISOString() } satisfies Change), { mode: 0o600 })
}

export function lastChange(path = paths.undo): Change | null {
  try {
    return existsSync(metaPath(path)) ? (JSON.parse(readFileSync(metaPath(path), "utf8")) as Change) : null
  } catch {
    return null
  }
}

export function undo(db: Database, path = paths.undo): Change {
  const change = lastChange(path)
  if (!change || !existsSync(path)) throw new LifeError("nothing to undo")

  db.exec("PRAGMA foreign_keys = OFF")
  try {
    db.query("ATTACH DATABASE ? AS saved").run(path)
    try {
      // A copy from before an upgrade has a different shape; it cannot come back.
      const version = (db.query("PRAGMA main.user_version").get() as { user_version: number }).user_version
      const saved = (db.query("PRAGMA saved.user_version").get() as { user_version: number }).user_version
      if (saved !== version) {
        db.exec("DETACH DATABASE saved")
        rmSync(path, { force: true })
        rmSync(metaPath(path), { force: true })
        throw new LifeError("nothing to undo")
      }
      db.transaction(() => {
        for (const table of TABLES) {
          db.exec(`DELETE FROM main.${table}`)
          db.exec(`INSERT INTO main.${table} SELECT * FROM saved.${table}`)
        }
      })()
    } finally {
      const attached = db.query("PRAGMA database_list").all() as { name: string }[]
      if (attached.some((d) => d.name === "saved")) db.exec("DETACH DATABASE saved")
    }
  } finally {
    db.exec("PRAGMA foreign_keys = ON")
  }

  rmSync(path, { force: true })
  rmSync(metaPath(path), { force: true })
  return change
}
