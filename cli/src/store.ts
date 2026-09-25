import type { Database } from "bun:sqlite"
import { EVERY_DAY, type Day } from "./dates"

export type HabitKind = "check" | "count" | "avoid"

export class LifeError extends Error {}

function need<T>(value: T | null | undefined, what: string): T {
  if (value === null || value === undefined) throw new LifeError(`${what} not found`)
  return value
}

function cleanTitle(title: string, what: string): string {
  const text = title.trim().replace(/\s+/g, " ")
  if (text === "") throw new LifeError(`${what} needs a name`)
  return text
}

// ---- tasks ----------------------------------------------------------------

export function addTask(db: Database, title: string, due: Day | null, today: Day): number {
  const row = db
    .query("INSERT INTO tasks (title, due, created_on) VALUES (?, ?, ?) RETURNING id")
    .get(cleanTitle(title, "A task"), due, today) as { id: number }
  return row.id
}

export function setTaskDone(db: Database, id: number, done: boolean, today: Day) {
  const changed = db.query("UPDATE tasks SET done_on = ? WHERE id = ?").run(done ? today : null, id)
  if (changed.changes === 0) throw new LifeError(`task ${id} not found`)
}

export function toggleTask(db: Database, id: number, today: Day) {
  const row = need(db.query("SELECT done_on FROM tasks WHERE id = ?").get(id) as { done_on: string | null } | null, `task ${id}`)
  setTaskDone(db, id, row.done_on === null, today)
}

export function setTaskDue(db: Database, id: number, due: Day | null) {
  const changed = db.query("UPDATE tasks SET due = ? WHERE id = ?").run(due, id)
  if (changed.changes === 0) throw new LifeError(`task ${id} not found`)
}

export function renameTask(db: Database, id: number, title: string) {
  const changed = db.query("UPDATE tasks SET title = ? WHERE id = ?").run(cleanTitle(title, "A task"), id)
  if (changed.changes === 0) throw new LifeError(`task ${id} not found`)
}

export function removeTask(db: Database, id: number) {
  const changed = db.query("DELETE FROM tasks WHERE id = ?").run(id)
  if (changed.changes === 0) throw new LifeError(`task ${id} not found`)
}

// ---- habits ---------------------------------------------------------------

export interface HabitInput {
  name: string
  kind: HabitKind
  target?: number
  unit?: string
  days?: number
}

export function addHabit(db: Database, input: HabitInput, today: Day): number {
  const target = input.kind === "count" ? Math.max(1, Math.round(input.target ?? 1)) : 1
  const days = input.kind === "avoid" ? EVERY_DAY : (input.days ?? EVERY_DAY)
  if (days <= 0 || days > EVERY_DAY) throw new LifeError("a habit needs at least one day")
  const position = (db.query("SELECT COALESCE(MAX(position), 0) + 1 AS p FROM habits").get() as { p: number }).p
  const row = db
    .query("INSERT INTO habits (name, kind, target, unit, days, position, created_on) VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id")
    .get(cleanTitle(input.name, "A habit"), input.kind, target, (input.unit ?? "").trim(), days, position, today) as { id: number }
  return row.id
}

interface HabitRow { id: number; kind: HabitKind; target: number }

function habit(db: Database, id: number): HabitRow {
  return need(db.query("SELECT id, kind, target FROM habits WHERE id = ?").get(id) as HabitRow | null, `habit ${id}`)
}

function logValue(db: Database, id: number, day: Day): number {
  const row = db.query("SELECT value FROM habit_logs WHERE habit_id = ? AND day = ?").get(id, day) as { value: number } | null
  return row?.value ?? 0
}

export function setHabitValue(db: Database, id: number, day: Day, value: number) {
  habit(db, id)
  const v = Math.max(0, Math.round(value))
  if (v === 0) db.query("DELETE FROM habit_logs WHERE habit_id = ? AND day = ?").run(id, day)
  else {
    db.query("INSERT INTO habit_logs (habit_id, day, value) VALUES (?, ?, ?) ON CONFLICT (habit_id, day) DO UPDATE SET value = excluded.value").run(id, day, v)
    // Backfilling a day before the habit existed means it started earlier.
    db.query("UPDATE habits SET created_on = ? WHERE id = ? AND created_on > ?").run(day, id, day)
  }
}

// One tap: check flips done, avoid flips "slipped", count jumps between
// empty and complete so a single click can still finish the day.
export function toggleHabit(db: Database, id: number, day: Day) {
  const h = habit(db, id)
  const current = logValue(db, id, day)
  if (h.kind === "count") setHabitValue(db, id, day, current >= h.target ? 0 : h.target)
  else setHabitValue(db, id, day, current > 0 ? 0 : 1)
}

export function bumpHabit(db: Database, id: number, day: Day, by: number) {
  const h = habit(db, id)
  if (h.kind !== "count") return toggleHabit(db, id, day)
  setHabitValue(db, id, day, logValue(db, id, day) + by)
}

export function updateHabit(db: Database, id: number, changes: Partial<HabitInput>) {
  const h = habit(db, id)
  if (changes.name !== undefined) db.query("UPDATE habits SET name = ? WHERE id = ?").run(cleanTitle(changes.name, "A habit"), id)
  if (changes.target !== undefined && h.kind === "count") db.query("UPDATE habits SET target = ? WHERE id = ?").run(Math.max(1, Math.round(changes.target)), id)
  if (changes.unit !== undefined) db.query("UPDATE habits SET unit = ? WHERE id = ?").run(changes.unit.trim(), id)
  if (changes.days !== undefined && h.kind !== "avoid") {
    if (changes.days <= 0 || changes.days > EVERY_DAY) throw new LifeError("a habit needs at least one day")
    db.query("UPDATE habits SET days = ? WHERE id = ?").run(changes.days, id)
  }
}

export function moveHabit(db: Database, id: number, direction: -1 | 1) {
  const ids = (db.query("SELECT id FROM habits ORDER BY position, id").all() as { id: number }[]).map((r) => r.id)
  const from = ids.indexOf(id)
  if (from < 0) throw new LifeError(`habit ${id} not found`)
  const to = from + direction
  if (to < 0 || to >= ids.length) return
  ;[ids[from], ids[to]] = [ids[to]!, ids[from]!]
  const update = db.query("UPDATE habits SET position = ? WHERE id = ?")
  db.transaction(() => ids.forEach((hid, i) => update.run(i + 1, hid)))()
}

export function removeHabit(db: Database, id: number) {
  const changed = db.query("DELETE FROM habits WHERE id = ?").run(id)
  if (changed.changes === 0) throw new LifeError(`habit ${id} not found`)
}

// ---- books ----------------------------------------------------------------

export function addBook(db: Database, title: string, totalPages: number, today: Day): number {
  const pages = Math.round(totalPages)
  if (!Number.isFinite(pages) || pages <= 0) throw new LifeError("a book needs a page count")
  const row = db
    .query("INSERT INTO books (title, total_pages, created_on) VALUES (?, ?, ?) RETURNING id")
    .get(cleanTitle(title, "A book"), pages, today) as { id: number }
  return row.id
}

function pagesRead(db: Database, id: number): number {
  return (db.query("SELECT COALESCE(SUM(pages), 0) AS n FROM reading_logs WHERE book_id = ?").get(id) as { n: number }).n
}

// Adds to what was already logged that day, so logging twice after two
// sittings just works. Negative numbers correct a typo. Crossing the last
// page finishes the book; dropping back below un-finishes it.
export function logReading(db: Database, id: number, pages: number, day: Day) {
  const book = need(db.query("SELECT total_pages FROM books WHERE id = ?").get(id) as { total_pages: number } | null, `book ${id}`)
  const read = pagesRead(db, id)
  const delta = Math.max(-read, Math.min(Math.round(pages), book.total_pages - read))
  if (delta === 0 && pages > 0) throw new LifeError("that book is already finished")

  db.transaction(() => {
    const current = db.query("SELECT pages FROM reading_logs WHERE book_id = ? AND day = ?").get(id, day) as { pages: number } | null
    const next = (current?.pages ?? 0) + delta
    if (next <= 0) db.query("DELETE FROM reading_logs WHERE book_id = ? AND day = ?").run(id, day)
    else db.query("INSERT INTO reading_logs (book_id, day, pages) VALUES (?, ?, ?) ON CONFLICT (book_id, day) DO UPDATE SET pages = excluded.pages").run(id, day, next)

    const done = read + delta >= book.total_pages
    db.query("UPDATE books SET finished_on = CASE WHEN ? THEN COALESCE(finished_on, ?) ELSE NULL END WHERE id = ?").run(done ? 1 : 0, day, id)
  })()
}

// The book you touched last, so `lifeos read 20` needs no id.
export function currentBookId(db: Database): number {
  const row = db.query(`
    SELECT b.id FROM books b
    LEFT JOIN reading_logs r ON r.book_id = b.id
    WHERE b.finished_on IS NULL
    GROUP BY b.id
    ORDER BY COALESCE(MAX(r.day), b.created_on) DESC, b.id DESC
    LIMIT 1
  `).get() as { id: number } | null
  return need(row, "a book you are reading").id
}

export function updateBook(db: Database, id: number, changes: { title?: string; totalPages?: number }) {
  need(db.query("SELECT id FROM books WHERE id = ?").get(id), `book ${id}`)
  if (changes.title !== undefined) db.query("UPDATE books SET title = ? WHERE id = ?").run(cleanTitle(changes.title, "A book"), id)
  if (changes.totalPages !== undefined) {
    const pages = Math.round(changes.totalPages)
    if (!Number.isFinite(pages) || pages <= 0) throw new LifeError("a book needs a page count")
    db.query("UPDATE books SET total_pages = ? WHERE id = ?").run(pages, id)
  }
}

export function removeBook(db: Database, id: number) {
  const changed = db.query("DELETE FROM books WHERE id = ?").run(id)
  if (changed.changes === 0) throw new LifeError(`book ${id} not found`)
}

// ---- events ---------------------------------------------------------------

export function addEvent(db: Database, title: string, day: Day, emoji: string, today: Day): number {
  const row = db
    .query("INSERT INTO events (title, day, emoji, created_on) VALUES (?, ?, ?, ?) RETURNING id")
    .get(cleanTitle(title, "An event"), day, emoji.trim(), today) as { id: number }
  return row.id
}

export function updateEvent(db: Database, id: number, changes: { title?: string; day?: Day; emoji?: string }) {
  need(db.query("SELECT id FROM events WHERE id = ?").get(id), `event ${id}`)
  if (changes.title !== undefined) db.query("UPDATE events SET title = ? WHERE id = ?").run(cleanTitle(changes.title, "An event"), id)
  if (changes.day !== undefined) db.query("UPDATE events SET day = ? WHERE id = ?").run(changes.day, id)
  if (changes.emoji !== undefined) db.query("UPDATE events SET emoji = ? WHERE id = ?").run(changes.emoji.trim(), id)
}

export function removeEvent(db: Database, id: number) {
  const changed = db.query("DELETE FROM events WHERE id = ?").run(id)
  if (changed.changes === 0) throw new LifeError(`event ${id} not found`)
}
