import type { Database } from "bun:sqlite"
import { renameSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"
import { addDays, diffDays, fromDay, isScheduled, nextBirthday, weekday, type Day } from "./dates"
import { paths, privateDir } from "./db"
import { SKIP, type HabitKind } from "./store"
import { clock, readSettings, shiftClock, type Settings } from "./settings"
import type { Change } from "./undo"

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
  focus: boolean
}

// future: not here yet · before: habit did not exist · off: not scheduled
// empty: scheduled, nothing logged · partial / done: count progress
// clean / slip: avoid habits · skip: a skipped day, neither kept nor missed
export type CellState = "future" | "before" | "off" | "empty" | "partial" | "done" | "clean" | "slip" | "skip"

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
  remindAt: string | null
  skipped: boolean
  canSkip: boolean
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

export interface Person {
  id: number
  name: string
  month: number
  day: number
  year: number | null
  next: Day
  daysLeft: number
  turning: number | null
}

export interface Insights {
  // Plain sentences, only the ones the data supports.
  lines: { icon: string; text: string }[]
  // The last 30 days of check-ins, oldest first; mood null when skipped.
  mood: { day: Day; mood: number | null; note: string | null }[]
  // Habit promises kept by weekday over the last 12 weeks, Monday first.
  weekdays: { rate: number; due: number }[]
  // Longest run each habit has had.
  records: { name: string; best: number; current: number }[]
}

// One week of keeping promises: scheduled habit days and the day's priorities.
export interface Week {
  start: Day
  end: Day
  due: number
  kept: number
  rate: number
  perfectDays: number
  tasksDone: number
  pages: number
  best: { name: string; rate: number } | null
  worst: { name: string; rate: number } | null
}

export type Phase = "morning" | "day" | "evening" | "night"

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
    prioritiesDone: number
    priorities: number
    dayComplete: boolean
    nextEvent: Event | null
    // Kept apart from events: birthdays belong to People.
    nextBirthday: Person | null
    reading: { id: number; title: string; percent: number } | null
  }
  tasks: { overdue: Task[]; today: Task[]; upcoming: Task[]; someday: Task[]; doneToday: Task[] }
  habits: Habit[]
  books: { reading: Book[]; finished: Book[] }
  events: Event[]
  day: {
    phase: Phase
    greeting: string
    planned: boolean
    shutdown: boolean
    needsPlan: boolean
    needsShutdown: boolean
    priorities: Task[]
    leftovers: Task[]
    // Unfinished habits get louder as the night goes on.
    alert: "none" | "warn" | "urgent"
    habitsLeft: string[]
    mood: number | null
    note: string | null
  }
  people: Person[]
  insights: Insights
  review: { thisWeek: Week; lastWeek: Week; due: boolean }
  settings: Settings
  // Set when this snapshot follows a change that can be undone.
  change: Change | null
}

// ---- tasks ----------------------------------------------------------------

function buildTasks(db: Database, today: Day): State["tasks"] {
  const rows = db.query(`
    SELECT id, title, due, done_on, focus_on FROM tasks
    WHERE dropped_on IS NULL AND (done_on IS NULL OR done_on = ?)
    ORDER BY due IS NULL, due, id
  `).all(today) as { id: number; title: string; due: Day | null; done_on: Day | null; focus_on: Day | null }[]

  const tasks: State["tasks"] = { overdue: [], today: [], upcoming: [], someday: [], doneToday: [] }
  for (const row of rows) {
    const daysUntil = row.due ? diffDays(today, row.due) : null
    const task: Task = { id: row.id, title: row.title, due: row.due, daysUntil, done: row.done_on !== null, focus: row.focus_on === today }
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
  remind_at?: string | null
}

function isDone(kind: HabitKind, target: number, value: number): boolean {
  if (value === SKIP) return false
  if (kind === "avoid") return value === 0
  return value >= target
}

function cellFor(h: HabitRow, day: Day, today: Day, value: number): Cell {
  if (day > today) return { day, state: "future", level: 0, value: 0 }
  if (day < h.created_on) return { day, state: "before", level: 0, value: 0 }

  if (h.kind === "avoid")
    return value > 0 ? { day, state: "slip", level: 0, value } : { day, state: "clean", level: 4, value: 0 }

  if (value === SKIP) return { day, state: "skip", level: 0, value: 0 }
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
    if (!isScheduled(h.days, day) || value === SKIP) continue
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
    if (logs.get(day) === SKIP) continue
    // Today only counts once it is kept, so the morning does not read as a failure.
    const done = isDone(h.kind, h.target, logs.get(day) ?? 0)
    if (day === today && !done) continue
    due++
    if (done) kept++
  }
  return due === 0 ? 0 : kept / due
}

function buildHabits(db: Database, today: Day): Habit[] {
  const rows = db.query("SELECT id, name, kind, target, unit, days, created_on, remind_at FROM habits ORDER BY position, id").all() as HabitRow[]
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

    const raw = logs.get(today) ?? 0
    const value = Math.max(0, raw)
    const streak = streakFor(h, logs, today)
    const weekStart = addDays(today, -weekday(today))
    let skipUsed = false
    for (let day = weekStart; day < today; day = addDays(day, 1)) if (logs.get(day) === SKIP) skipUsed = true
    return {
      id: h.id,
      name: h.name,
      kind: h.kind,
      target: h.target,
      unit: h.unit,
      days: h.days,
      scheduledToday: h.kind === "avoid" || isScheduled(h.days, today),
      value,
      done: isDone(h.kind, h.target, raw),
      progress: h.kind === "count" ? Math.min(1, value / h.target) : isDone(h.kind, h.target, raw) ? 1 : 0,
      streak,
      onFire: streak >= FIRE_STREAK,
      rate30: rateFor(h, logs, today),
      remindAt: h.remind_at ?? null,
      skipped: raw === SKIP,
      canSkip: h.kind !== "avoid" && !skipUsed,
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
  const events: Event[] = rows.map((e) => {
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
  return events
}

function buildPeople(db: Database, today: Day): Person[] {
  const rows = db.query("SELECT id, name, month, day, year FROM people").all() as
    { id: number; name: string; month: number; day: number; year: number | null }[]
  return rows
    .map((p) => {
      const next = nextBirthday({ month: p.month, day: p.day, year: p.year }, today)
      return {
        id: p.id,
        name: p.name,
        month: p.month,
        day: p.day,
        year: p.year,
        next,
        daysLeft: diffDays(today, next),
        turning: p.year ? fromDay(next).getFullYear() - p.year : null,
      }
    })
    .sort((a, b) => a.daysLeft - b.daysLeft || a.name.localeCompare(b.name))
}

// ---- insights -----------------------------------------------------------------

const WEEKDAY_NAMES = ["Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays"]

function longestRun(h: HabitRow, logs: Map<Day, number>, today: Day): number {
  let best = 0
  let run = 0
  for (let day = h.created_on; day <= today; day = addDays(day, 1)) {
    const value = logs.get(day) ?? 0
    if (h.kind === "avoid") {
      run = value > 0 ? 0 : run + 1
    } else {
      if (!isScheduled(h.days, day) || value === SKIP) continue
      if (isDone(h.kind, h.target, value)) run++
      else if (day !== today) run = 0
    }
    best = Math.max(best, run)
  }
  return best
}

export function buildInsights(db: Database, today: Day, habits: Habit[]): Insights {
  const lines: Insights["lines"] = []
  const since = addDays(today, -83) // twelve weeks
  const rows = db.query("SELECT id, name, kind, target, unit, days, created_on FROM habits").all() as HabitRow[]
  const logQuery = db.query("SELECT day, value FROM habit_logs WHERE habit_id = ?")

  // Promises by weekday, and by day for comparing with mood.
  const weekdays = Array.from({ length: 7 }, () => ({ due: 0, kept: 0 }))
  const perDay = new Map<Day, { due: number; kept: number }>()
  const records: Insights["records"] = []
  let recent = { due: 0, kept: 0 }
  let before = { due: 0, kept: 0 }

  for (const h of rows) {
    const logs = new Map<Day, number>()
    for (const l of logQuery.all(h.id) as { day: Day; value: number }[]) logs.set(l.day, l.value)
    const current = habits.find((x) => x.id === h.id)?.streak ?? 0
    records.push({ name: h.name, best: Math.max(longestRun(h, logs, today), current), current })

    for (let day = since > h.created_on ? since : h.created_on; day < today; day = addDays(day, 1)) {
      if (h.kind !== "avoid" && !isScheduled(h.days, day)) continue
      const value = logs.get(day) ?? 0
      if (value === SKIP) continue
      const done = isDone(h.kind, h.target, value)
      const w = weekdays[weekday(day)]!
      w.due++
      if (done) w.kept++
      const d = perDay.get(day) ?? { due: 0, kept: 0 }
      d.due++
      if (done) d.kept++
      perDay.set(day, d)
      const bucket = day >= addDays(today, -30) ? recent : day >= addDays(today, -60) ? before : null
      if (bucket) {
        bucket.due++
        if (done) bucket.kept++
      }
    }
  }

  const rated = weekdays.map((w, i) => ({ i, rate: w.due ? w.kept / w.due : 0, due: w.due })).filter((w) => w.due >= 3)
  if (rated.length >= 4) {
    const sorted = [...rated].sort((a, b) => b.rate - a.rate)
    const top = sorted[0]!
    const low = sorted[sorted.length - 1]!
    if (top.rate - low.rate >= 0.15)
      lines.push({ icon: "calendar", text: `You keep habits best on ${WEEKDAY_NAMES[top.i]} (${Math.round(top.rate * 100)}%) and slip most on ${WEEKDAY_NAMES[low.i]} (${Math.round(low.rate * 100)}%).` })
  }

  if (recent.due >= 10 && before.due >= 10) {
    const delta = Math.round((recent.kept / recent.due - before.kept / before.due) * 100)
    if (Math.abs(delta) >= 5)
      lines.push({ icon: delta > 0 ? "up" : "down", text: `Habits kept are ${delta > 0 ? "up" : "down"} ${Math.abs(delta)}% on the month before.` })
  }

  // Reading: weekdays against weekends.
  const reading = db.query("SELECT day, SUM(pages) AS pages FROM reading_logs WHERE day >= ? GROUP BY day").all(since) as { day: Day; pages: number }[]
  if (reading.length >= 8) {
    let wk = 0, wkDays = 0, we = 0, weDays = 0
    for (const r of reading) {
      if (weekday(r.day) >= 5) { we += r.pages; weDays++ } else { wk += r.pages; wkDays++ }
    }
    if (wkDays >= 3 && weDays >= 2) {
      const a = wk / wkDays, b = we / weDays
      const ratio = Math.max(a, b) / Math.max(1, Math.min(a, b))
      if (ratio >= 1.3)
        lines.push({ icon: "book", text: `On reading days you read ${b > a ? "more at weekends" : "more on weekdays"}: ${Math.round(b > a ? b : a)} pages against ${Math.round(b > a ? a : b)}.` })
    }
  }

  // Mood: how kept days feel against the rest.
  const checkins = db.query("SELECT day, mood, note FROM days WHERE day >= ? AND mood IS NOT NULL").all(addDays(today, -89)) as { day: Day; mood: number; note: string | null }[]
  const kept: number[] = [], missed: number[] = []
  for (const c of checkins) {
    const d = perDay.get(c.day)
    if (!d || d.due === 0) continue
    ;(d.kept === d.due ? kept : missed).push(c.mood)
  }
  const avg = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length
  if (kept.length >= 3 && missed.length >= 3 && Math.abs(avg(kept) - avg(missed)) >= 0.3)
    lines.push({ icon: "mood", text: `Days you keep every habit feel ${avg(kept) > avg(missed) ? "better" : "harder"}: ${avg(kept).toFixed(1)} against ${avg(missed).toFixed(1)} out of 5.` })

  const record = [...records].sort((a, b) => b.best - a.best)[0]
  if (record && record.best >= 3)
    lines.push({ icon: "fire", text: record.current >= record.best
      ? `${record.name} is on its best run ever: ${record.best} days.`
      : `Your longest run: ${record.name}, ${record.best} days (now ${record.current}).` })

  const tasks = (db.query("SELECT COUNT(*) AS n FROM tasks WHERE done_on >= ?").get(addDays(today, -27)) as { n: number }).n
  if (tasks >= 4) lines.push({ icon: "check", text: `You finish about ${Math.round(tasks / 4)} tasks a week.` })

  const moodByDay = new Map(checkins.map((c) => [c.day, c]))
  const mood: Insights["mood"] = []
  for (let i = 29; i >= 0; i--) {
    const day = addDays(today, -i)
    const c = moodByDay.get(day)
    mood.push({ day, mood: c?.mood ?? null, note: c?.note ?? null })
  }

  return {
    lines,
    mood,
    weekdays: weekdays.map((w) => ({ rate: w.due ? w.kept / w.due : 0, due: w.due })),
    records: records.filter((r) => r.best > 0).sort((a, b) => b.best - a.best),
  }
}

// ---- the week ---------------------------------------------------------------

// Promises for a stretch of days: every scheduled habit day (skips excluded,
// avoid habits every day) and every priority set. A promise is kept when the
// habit was done or the priority finished.
export function buildWeek(db: Database, start: Day, end: Day, today: Day): Week {
  const last = end < today ? end : today
  const habits = db.query("SELECT id, name, kind, target, days, created_on FROM habits").all() as
    (HabitRow & { name: string })[]
  const logQuery = db.query("SELECT day, value FROM habit_logs WHERE habit_id = ? AND day BETWEEN ? AND ?")

  let due = 0
  let kept = 0
  const perDay = new Map<Day, { due: number; kept: number }>()
  const rates: { name: string; rate: number }[] = []

  for (const h of habits) {
    const logs = new Map<Day, number>()
    for (const l of logQuery.all(h.id, start, last) as { day: Day; value: number }[]) logs.set(l.day, l.value)
    let hDue = 0
    let hKept = 0
    for (let day = start; day <= last; day = addDays(day, 1)) {
      if (day < h.created_on) continue
      if (h.kind !== "avoid" && !isScheduled(h.days, day)) continue
      const value = logs.get(day) ?? 0
      if (value === SKIP) continue
      const done = isDone(h.kind, h.target, value)
      // Today is still being played; only count it once it is won.
      if (day === today && !done) continue
      hDue++
      if (done) hKept++
      const d = perDay.get(day) ?? { due: 0, kept: 0 }
      d.due++
      if (done) d.kept++
      perDay.set(day, d)
    }
    due += hDue
    kept += hKept
    if (hDue >= 2) rates.push({ name: h.name, rate: hKept / hDue })
  }

  const focus = db.query(`
    SELECT COUNT(*) AS due, COUNT(done_on) AS kept FROM tasks
    WHERE focus_on BETWEEN ? AND ? AND dropped_on IS NULL AND (focus_on < ? OR done_on IS NOT NULL)
  `).get(start, last, today) as { due: number; kept: number }
  due += focus.due
  kept += focus.kept

  rates.sort((a, b) => b.rate - a.rate)
  const tasksDone = (db.query("SELECT COUNT(*) AS n FROM tasks WHERE done_on BETWEEN ? AND ?").get(start, last) as { n: number }).n
  const pages = (db.query("SELECT COALESCE(SUM(pages), 0) AS n FROM reading_logs WHERE day BETWEEN ? AND ?").get(start, last) as { n: number }).n
  let perfectDays = 0
  for (const d of perDay.values()) if (d.due > 0 && d.kept === d.due) perfectDays++

  return {
    start,
    end,
    due,
    kept,
    rate: due === 0 ? 0 : kept / due,
    perfectDays,
    tasksDone,
    pages,
    best: rates[0] ?? null,
    worst: rates.length > 1 && rates[rates.length - 1]!.rate < rates[0]!.rate ? rates[rates.length - 1]! : null,
  }
}

// ---- the day ------------------------------------------------------------------

function phaseFor(time: string, settings: Settings): Phase {
  if (time < "04:00") return "night"
  if (time < "12:00") return "morning"
  if (time < settings.shutdown) return "day"
  if (time < settings.bedtime) return "evening"
  return "night"
}

const GREETINGS: Record<Phase, string> = {
  morning: "Good morning",
  day: "Good afternoon",
  evening: "Good evening",
  night: "Late night",
}

export function buildState(db: Database, today: Day, now = new Date()): State {
  const settings = readSettings(db)
  const tasks = buildTasks(db, today)
  const habits = buildHabits(db, today)
  const books = buildBooks(db, today)
  const people = buildPeople(db, today)
  const events = buildEvents(db, today)
  const due = habits.filter((h) => h.scheduledToday && !h.skipped)
  const current = books.reading[0]
  const time = clock(now)

  const dayRow = db.query("SELECT planned_at, shutdown_at, mood, note FROM days WHERE day = ?").get(today) as
    { planned_at: string | null; shutdown_at: string | null; mood: number | null; note: string | null } | null
  const planned = !!dayRow?.planned_at
  const shutdown = !!dayRow?.shutdown_at
  const phase = phaseFor(time, settings)
  const leftovers = [...tasks.overdue, ...tasks.today]
  const priorities = [...tasks.overdue, ...tasks.today, ...tasks.upcoming, ...tasks.someday, ...tasks.doneToday].filter((t) => t.focus)
  const habitsLeft = due.filter((h) => !h.done).map((h) => h.name)

  const alert: State["day"]["alert"] = habitsLeft.length === 0
    ? "none"
    : time >= shiftClock(settings.bedtime, -60) ? "urgent"
    : time >= shiftClock(settings.remind, 120) ? "warn"
    : "none"

  const weekStart = addDays(today, -weekday(today))
  const thisWeek = buildWeek(db, weekStart, addDays(weekStart, 6), today)
  const lastWeek = buildWeek(db, addDays(weekStart, -7), addDays(weekStart, -1), today)
  const reviewed = (db.query("SELECT value FROM settings WHERE key = 'reviewed'").get() as { value: string } | null)?.value
  const anyHistory = (db.query("SELECT COUNT(*) AS n FROM habits WHERE created_on < ?").get(weekStart) as { n: number }).n > 0

  const tasksTotal = tasks.overdue.length + tasks.today.length + tasks.doneToday.length
  const doneCount = due.filter((h) => h.done).length + tasks.doneToday.length
  const totalCount = due.length + tasksTotal

  return {
    version: 1,
    generatedAt: now.toISOString(),
    today,
    summary: {
      habitsDue: due.length,
      habitsDone: due.filter((h) => h.done).length,
      tasksLeft: leftovers.length,
      tasksDoneToday: tasks.doneToday.length,
      overdue: tasks.overdue.length,
      fire: habits.filter((h) => h.onFire).length,
      prioritiesDone: priorities.filter((t) => t.done).length,
      priorities: priorities.length,
      dayComplete: totalCount > 0 && doneCount === totalCount,
      nextEvent: events[0] ?? null,
      nextBirthday: people[0] ?? null,
      reading: current ? { id: current.id, title: current.title, percent: current.percent } : null,
    },
    tasks,
    habits,
    books,
    events,
    day: {
      phase,
      greeting: GREETINGS[phase],
      planned,
      shutdown,
      needsPlan: settings.plan === "on" && !planned && time >= "04:00" && time < settings.shutdown,
      needsShutdown: !shutdown && time >= settings.shutdown && leftovers.length > 0,
      priorities,
      leftovers,
      alert,
      habitsLeft,
      mood: dayRow?.mood ?? null,
      note: dayRow?.note ?? null,
    },
    people,
    insights: buildInsights(db, today, habits),
    review: {
      thisWeek,
      lastWeek,
      due: anyHistory && lastWeek.due > 0 && reviewed !== lastWeek.start,
    },
    settings,
    change: null,
  }
}

// Written beside, then renamed over, so the plugin's watcher never sees a
// half-written file.
export function writeState(state: State, path = paths.state) {
  privateDir(dirname(path))
  const tmp = `${path}.${process.pid}.tmp`
  // The mode applies at creation, so the snapshot is never world-readable,
  // not even for the moment before the rename.
  writeFileSync(tmp, JSON.stringify(state), { mode: 0o600 })
  renameSync(tmp, path)
}
