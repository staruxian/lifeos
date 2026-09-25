import type { Database } from "bun:sqlite"
import { mkdirSync, renameSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"
import { addDays, diffDays, isScheduled, weekday, type Day } from "./dates"
import { paths } from "./db"
import type { HabitKind } from "./store"

// The snapshot is the whole contract with the shell plugin: every number the
// panel shows is computed here, so the QML side only lays things out.

export const HEAT_WEEKS = 18
export const FIRE_STREAK = 3
const PACE_WINDOW = 14

export interface Task {
  id: number
  title: string
  due: Day | null
  daysUntil: number | null
  done: boolean
}

// future: not here yet · before: habit did not exist · off: not scheduled
// empty: scheduled, nothing logged · partial / done: count progress
// clean / slip: avoid habits
export type CellState = "future" | "before" | "off" | "empty" | "partial" | "done" | "clean" | "slip"

export interface Cell {
  day: Day
  state: CellState
  level: number // 0–4, GitHub-style intensity
  value: number
}

export interface Habit {
  id: number
  name: string
  kind: HabitKind
  target: number
  unit: string
  days: number
  scheduledToday: boolean
  value: number
  done: boolean
  progress: number
  streak: number
  onFire: boolean
  rate30: number
  heat: Cell[][] // weeks (oldest first) × 7 days (Monday first)
}

export interface Book {
  id: number
  title: string
  total: number
  read: number
  remaining: number
  percent: number
  today: number
  pace: number
  etaDays: number | null
  etaDay: Day | null
  startedOn: Day
  finishedOn: Day | null
  recent: { day: Day; pages: number }[]
}

export interface Event {
  id: number
  title: string
  day: Day
  emoji: string
  daysLeft: number
  progress: number
}

export interface State {
  version: 1
  generatedAt: string
  today: Day
  summary: {
    habitsDue: number
    habitsDone: number
    tasksLeft: number
    tasksDoneToday: number
    overdue: number
    fire: number
    nextEvent: Event | null
    reading: { id: number; title: string; percent: number } | null
  }
  tasks: { overdue: Task[]; today: Task[]; upcoming: Task[]; someday: Task[]; doneToday: Task[] }
  habits: Habit[]
  books: { reading: Book[]; finished: Book[] }
  events: Event[]
}

// ---- tasks ----------------------------------------------------------------

function buildTasks(db: Database, today: Day): State["tasks"] {
  const rows = db.query(`
    SELECT id, title, due, done_on FROM tasks
    WHERE done_on IS NULL OR done_on = ?
    ORDER BY due IS NULL, due, id
  `).all(today) as { id: number; title: string; due: Day | null; done_on: Day | null }[]

  const tasks: State["tasks"] = { overdue: [], today: [], upcoming: [], someday: [], doneToday: [] }
  for (const row of rows) {
    const daysUntil = row.due ? diffDays(today, row.due) : null
    const task: Task = { id: row.id, title: row.title, due: row.due, daysUntil, done: row.done_on !== null }
    if (task.done) tasks.doneToday.push(task)
    else if (daysUntil === null) tasks.someday.push(task)
    else if (daysUntil < 0) tasks.overdue.push(task)
    else if (daysUntil === 0) tasks.today.push(task)
    else tasks.upcoming.push(task)
  }
  return tasks
}

// ---- habits ---------------------------------------------------------------

interface HabitRow {
  id: number
  name: string
  kind: HabitKind
  target: number
  unit: string
  days: number
  created_on: Day
}

function isDone(kind: HabitKind, target: number, value: number): boolean {
  if (kind === "avoid") return value === 0
  return value >= target
}

function cellFor(h: HabitRow, day: Day, today: Day, value: number): Cell {
  if (day > today) return { day, state: "future", level: 0, value: 0 }
  if (day < h.created_on) return { day, state: "before", level: 0, value: 0 }

  if (h.kind === "avoid")
    return value > 0 ? { day, state: "slip", level: 0, value } : { day, state: "clean", level: 4, value: 0 }

  const scheduled = isScheduled(h.days, day)
  if (value <= 0) return { day, state: scheduled ? "empty" : "off", level: 0, value: 0 }
  const ratio = Math.min(1, value / h.target)
  if (ratio >= 1) return { day, state: "done", level: 4, value }
  return { day, state: "partial", level: ratio < 0.34 ? 1 : ratio < 0.67 ? 2 : 3, value }
}

// Consecutive scheduled days kept, ending today. An unfinished today does
// not break the chain yet — the day is not over. Unscheduled days neither
// count nor break it. Avoid habits count clean days since the last slip.
function streakFor(h: HabitRow, logs: Map<Day, number>, today: Day): number {
  let streak = 0
  for (let day = today; day >= h.created_on; day = addDays(day, -1)) {
    const value = logs.get(day) ?? 0
    if (h.kind === "avoid") {
      if (value > 0) break
      streak++
      continue
    }
    if (!isScheduled(h.days, day)) continue
    if (isDone(h.kind, h.target, value)) streak++
    else if (day !== today) break
  }
  return streak
}

function rateFor(h: HabitRow, logs: Map<Day, number>, today: Day): number {
  let due = 0
  let kept = 0
  for (let i = 0; i < 30; i++) {
    const day = addDays(today, -i)
    if (day < h.created_on) break
    if (h.kind !== "avoid" && !isScheduled(h.days, day)) continue
    // Today only counts once it is kept, so the morning does not read as a failure.
    const done = isDone(h.kind, h.target, logs.get(day) ?? 0)
    if (day === today && !done) continue
    due++
    if (done) kept++
  }
  return due === 0 ? 0 : kept / due
}

function buildHabits(db: Database, today: Day): Habit[] {
  const rows = db.query("SELECT id, name, kind, target, unit, days, created_on FROM habits ORDER BY position, id").all() as HabitRow[]
  const gridStart = addDays(today, -weekday(today) - (HEAT_WEEKS - 1) * 7)
  const logQuery = db.query("SELECT day, value FROM habit_logs WHERE habit_id = ?")

  return rows.map((h) => {
    const logs = new Map<Day, number>()
    for (const log of logQuery.all(h.id) as { day: Day; value: number }[]) logs.set(log.day, log.value)

    const heat: Cell[][] = []
    for (let w = 0; w < HEAT_WEEKS; w++) {
      const week: Cell[] = []
      for (let d = 0; d < 7; d++) {
        const day = addDays(gridStart, w * 7 + d)
        week.push(cellFor(h, day, today, logs.get(day) ?? 0))
      }
      heat.push(week)
    }

    const value = logs.get(today) ?? 0
    const streak = streakFor(h, logs, today)
    return {
      id: h.id,
      name: h.name,
      kind: h.kind,
      target: h.target,
      unit: h.unit,
      days: h.days,
      scheduledToday: h.kind === "avoid" || isScheduled(h.days, today),
      value,
      done: isDone(h.kind, h.target, value),
      progress: h.kind === "count" ? Math.min(1, value / h.target) : isDone(h.kind, h.target, value) ? 1 : 0,
      streak,
      onFire: streak >= FIRE_STREAK,
      rate30: rateFor(h, logs, today),
      heat,
    }
  })
}

// ---- books ----------------------------------------------------------------

function buildBooks(db: Database, today: Day): State["books"] {
  const rows = db.query("SELECT id, title, total_pages, created_on, finished_on FROM books ORDER BY id").all() as {
    id: number; title: string; total_pages: number; created_on: Day; finished_on: Day | null
  }[]
  const logQuery = db.query("SELECT day, pages FROM reading_logs WHERE book_id = ?")

  const books = rows.map((b): Book => {
    const logs = new Map<Day, number>()
    let read = 0
    for (const log of logQuery.all(b.id) as { day: Day; pages: number }[]) {
      logs.set(log.day, log.pages)
      read += log.pages
    }
    read = Math.min(read, b.total_pages)
    const remaining = b.total_pages - read

    const firstDay = [...logs.keys()].sort()[0] ?? b.created_on
    const startedOn = firstDay < b.created_on ? firstDay : b.created_on
    const windowDays = Math.max(1, Math.min(PACE_WINDOW, diffDays(startedOn, today) + 1))
    let windowPages = 0
    const recent: Book["recent"] = []
    for (let i = PACE_WINDOW - 1; i >= 0; i--) {
      const day = addDays(today, -i)
      const pages = logs.get(day) ?? 0
      recent.push({ day, pages })
      if (i < windowDays) windowPages += pages
    }
    const pace = windowPages / windowDays
    const etaDays = remaining > 0 && pace > 0 ? Math.ceil(remaining / pace) : remaining === 0 ? 0 : null

    return {
      id: b.id,
      title: b.title,
      total: b.total_pages,
      read,
      remaining,
      percent: read / b.total_pages,
      today: logs.get(today) ?? 0,
      pace: Math.round(pace * 10) / 10,
      etaDays,
      etaDay: etaDays === null ? null : addDays(today, etaDays),
      startedOn,
      finishedOn: b.finished_on,
      recent,
    }
  })

  const reading = books.filter((b) => !b.finishedOn)
  // Most recently read first: that is the one you will log next.
  const lastRead = (b: Book) => [...b.recent].reverse().find((r) => r.pages > 0)?.day ?? b.startedOn
  reading.sort((a, b) => (lastRead(b) > lastRead(a) ? 1 : lastRead(b) < lastRead(a) ? -1 : b.id - a.id))
  const finished = books.filter((b) => b.finishedOn).sort((a, b) => (a.finishedOn! < b.finishedOn! ? 1 : -1))
  return { reading, finished }
}

// ---- events ---------------------------------------------------------------

// Past events simply stop appearing; the rows stay, so nothing is lost if the
// date was mistyped.
function buildEvents(db: Database, today: Day): Event[] {
  const rows = db.query("SELECT id, title, day, emoji, created_on FROM events WHERE day >= ? ORDER BY day, id").all(today) as {
    id: number; title: string; day: Day; emoji: string; created_on: Day
  }[]
  return rows.map((e) => {
    const span = diffDays(e.created_on, e.day)
    const elapsed = diffDays(e.created_on, today)
    return {
      id: e.id,
      title: e.title,
      day: e.day,
      emoji: e.emoji,
      daysLeft: diffDays(today, e.day),
      progress: span <= 0 ? 1 : Math.max(0, Math.min(1, elapsed / span)),
    }
  })
}

// ---- snapshot -------------------------------------------------------------

export function buildState(db: Database, today: Day, now = new Date()): State {
  const tasks = buildTasks(db, today)
  const habits = buildHabits(db, today)
  const books = buildBooks(db, today)
  const events = buildEvents(db, today)
  const due = habits.filter((h) => h.scheduledToday)
  const current = books.reading[0]

  return {
    version: 1,
    generatedAt: now.toISOString(),
    today,
    summary: {
      habitsDue: due.length,
      habitsDone: due.filter((h) => h.done).length,
      tasksLeft: tasks.overdue.length + tasks.today.length,
      tasksDoneToday: tasks.doneToday.length,
      overdue: tasks.overdue.length,
      fire: habits.filter((h) => h.onFire).length,
      nextEvent: events[0] ?? null,
      reading: current ? { id: current.id, title: current.title, percent: current.percent } : null,
    },
    tasks,
    habits,
    books,
    events,
  }
}

// Written beside, then renamed over, so the plugin's watcher never sees a
// half-written file.
export function writeState(state: State, path = paths.state) {
  mkdirSync(dirname(path), { recursive: true })
  const tmp = `${path}.${process.pid}.tmp`
  writeFileSync(tmp, JSON.stringify(state))
  renameSync(tmp, path)
}
