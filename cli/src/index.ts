#!/usr/bin/env bun
import type { Database } from "bun:sqlite"
import { addDays, parseDay, parseWeekdays, today as todayDay, weekday, type Day } from "./dates"
import { openDb, paths } from "./db"
import { tick } from "./notify"
import { printBooks, printEvents, printHabits, printOverview, printPlan, printSettings, printTasks, printWeek } from "./print"
import { parseQuick } from "./quick"
import { readSettings, writeSetting } from "./settings"
import { buildState, writeState, type State } from "./state"
import * as store from "./store"
import { LifeError, type HabitKind } from "./store"
import { capture, saveSnapshot, undo } from "./undo"

const BOOLEAN_FLAGS = new Set(["json", "help", "off"])

interface Args {
  words: string[]
  flags: Map<string, string>
}

function parseArgs(argv: string[]): Args {
  const words: string[] = []
  const flags = new Map<string, string>()
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!
    if (arg === "--") {
      words.push(...argv.slice(i + 1))
      break
    }
    if (arg.startsWith("--")) {
      const [name, inline] = arg.slice(2).split(/=(.*)/s, 2) as [string, string | undefined]
      if (BOOLEAN_FLAGS.has(name)) flags.set(name, "true")
      else if (inline !== undefined) flags.set(name, inline)
      else {
        const value = argv[++i]
        if (value === undefined) throw new LifeError(`--${name} needs a value`)
        flags.set(name, value)
      }
    } else if (arg === "-h") flags.set("help", "true")
    else words.push(arg)
  }
  return { words, flags }
}

function id(value: string | undefined, what: string): number {
  const n = Number(value)
  if (!value || !Number.isInteger(n) || n <= 0) throw new LifeError(`which ${what}? give its number`)
  return n
}

function int(value: string | undefined, what: string): number {
  const n = Number(value)
  if (value === undefined || value === "" || !Number.isFinite(n)) throw new LifeError(`${what} must be a number`)
  return Math.round(n)
}

function day(value: string, today: Day): Day {
  const parsed = parseDay(value, today)
  if (!parsed) throw new LifeError(`could not understand the date "${value}"`)
  return parsed
}

function optionalDay(value: string | undefined, today: Day): Day | null {
  if (value === undefined) return null
  const v = value.trim().toLowerCase()
  if (v === "" || v === "none" || v === "someday" || v === "no") return null
  return day(value, today)
}

function kind(value: string | undefined): HabitKind {
  const v = (value ?? "check").toLowerCase()
  if (v === "check" || v === "yes" || v === "yesno") return "check"
  if (v === "count" || v === "amount" || v === "number") return "count"
  if (v === "avoid" || v === "quit" || v === "break") return "avoid"
  throw new LifeError(`habit kind must be check, count or avoid`)
}

function weekdays(value: string | undefined): number | undefined {
  if (value === undefined) return undefined
  const mask = parseWeekdays(value)
  if (mask === null) throw new LifeError(`could not understand the days "${value}"`)
  return mask
}

// A trailing `due:fri` in a task title is lifted out as the due date.
function splitDue(words: string[]): { title: string; due?: string } {
  const rest: string[] = []
  let due: string | undefined
  for (const w of words) {
    const m = w.match(/^due:(.+)$/i)
    if (m) due = m[1]
    else rest.push(w)
  }
  return { title: rest.join(" "), due }
}

function quoted(text: string): string {
  return `“${text.length > 40 ? text.slice(0, 39) + "…" : text}”`
}

type Printer = (state: State) => void
const quiet: Printer = () => {}

interface Context {
  db: Database
  today: Day
  now: Date
  flags: Map<string, string>
  // Set by commands that change data, with the database as it was before.
  change: string | null
  before: Uint8Array | null
  // Extra JSON for the caller (the panel), e.g. a quick-add preview.
  extra: Record<string, unknown>
}

// Remembers the database for undo and what the change was; main saves both
// once the change has gone through.
function changing(ctx: Context, label: string) {
  if (!ctx.before) ctx.before = capture(ctx.db)
  ctx.change = label
}

// Strict mode keeps the record honest: today and yesterday only.
function logDay(ctx: Context): Day {
  const on = ctx.flags.has("day") ? day(ctx.flags.get("day")!, ctx.today) : ctx.today
  if (on > ctx.today) throw new LifeError("that day has not happened yet")
  if (readSettings(ctx.db).strict === "on" && on < addDays(ctx.today, -1))
    throw new LifeError("strict mode: only today and yesterday can be logged")
  return on
}

function run(ctx: Context, words: string[]): Printer {
  const { db, today, flags: f } = ctx
  const [group = "", verb = "", ...rest] = words

  switch (group) {
    case "":
    case "today":
      return printOverview
    case "state":
      return quiet

    case "add":
      return run(ctx, ["task", "add", ...words.slice(1)])
    case "read":
      return run(ctx, ["book", "log", f.get("book") ?? String(store.currentBookId(db)), ...words.slice(1)])

    case "quick": {
      const parsed = parseQuick(words.slice(1).join(" "), today)
      if (!parsed) throw new LifeError("type a task, e.g. “pay rent fri”")
      if (parsed.kind === "read") return run(ctx, ["read", String(parsed.pages)])
      changing(ctx, `Added ${quoted(parsed.title)}`)
      const taskId = store.addTask(db, parsed.title, parsed.due, today)
      if (parsed.focus) store.setFocus(db, taskId, true, today)
      return printTasks
    }
    case "parse":
      ctx.extra.parsed = parseQuick(words.slice(1).join(" "), today)
      return () => console.log(JSON.stringify(ctx.extra.parsed))

    case "undo": {
      const change = undo(db)
      ctx.extra.undone = change.label
      return () => console.log(`Undid: ${change.label}`)
    }

    case "task":
    case "tasks": {
      const taskId = () => id(rest[0], "task")
      switch (verb) {
        case "":
        case "ls":
          return printTasks
        case "add": {
          const { title, due } = splitDue(rest)
          changing(ctx, `Added ${quoted(title)}`)
          store.addTask(db, title, optionalDay(f.get("due") ?? due, today), today)
          return printTasks
        }
        case "done":
          changing(ctx, `Completed ${quoted(store.taskTitle(db, taskId()))}`)
          store.setTaskDone(db, taskId(), true, today)
          return printTasks
        case "undo":
          changing(ctx, `Reopened ${quoted(store.taskTitle(db, taskId()))}`)
          store.setTaskDone(db, taskId(), false, today)
          return printTasks
        case "toggle":
          changing(ctx, `Checked ${quoted(store.taskTitle(db, taskId()))}`)
          store.toggleTask(db, taskId(), today)
          return printTasks
        case "due": {
          const due = optionalDay(rest.slice(1).join(" ") || "none", today)
          changing(ctx, `Moved ${quoted(store.taskTitle(db, taskId()))}`)
          store.setTaskDue(db, taskId(), due)
          return printTasks
        }
        case "rename":
          changing(ctx, `Renamed ${quoted(store.taskTitle(db, taskId()))}`)
          store.renameTask(db, taskId(), rest.slice(1).join(" "))
          return printTasks
        case "focus":
          changing(ctx, f.has("off") ? "Removed a priority" : `Prioritised ${quoted(store.taskTitle(db, taskId()))}`)
          store.setFocus(db, taskId(), !f.has("off"), today)
          return printPlan
        case "drop":
          changing(ctx, `Dropped ${quoted(store.taskTitle(db, taskId()))}`)
          store.dropTask(db, taskId(), today)
          return printTasks
        case "rm":
          changing(ctx, `Deleted ${quoted(store.taskTitle(db, taskId()))}`)
          store.removeTask(db, taskId())
          return printTasks
      }
      break
    }

    case "plan":
      switch (verb) {
        case "":
        case "ls":
          return printPlan
        case "start":
        case "done":
          changing(ctx, "Planned the day")
          store.markPlanned(db, today, ctx.now.toISOString())
          return printPlan
      }
      break

    case "shutdown":
      changing(ctx, "Shut down the day")
      store.markShutdown(db, today, ctx.now.toISOString())
      return printOverview

    case "review":
      if (verb === "seen") {
        const lastWeekStart = addDays(today, -weekday(today) - 7)
        db.query("INSERT INTO settings (key, value) VALUES ('reviewed', ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value").run(lastWeekStart)
        return quiet
      }
      return printWeek

    case "tick":
      return quiet

    case "set":
      if (!verb) return printSettings
      changing(ctx, `Changed ${verb}`)
      writeSetting(db, verb, rest.join(" "))
      return printSettings
    case "settings":
      return printSettings

    case "habit":
    case "habits": {
      const habitId = () => id(rest[0], "habit")
      switch (verb) {
        case "":
        case "ls":
          return printHabits
        case "add":
          changing(ctx, `Added ${quoted(rest.join(" "))}`)
          store.addHabit(db, {
            name: rest.join(" "),
            kind: kind(f.get("kind")),
            target: f.has("target") ? int(f.get("target"), "target") : undefined,
            unit: f.get("unit"),
            days: weekdays(f.get("days")),
          }, today)
          return printHabits
        case "toggle": {
          const on = logDay(ctx)
          changing(ctx, `Logged ${quoted(store.habitName(db, habitId()))}`)
          store.toggleHabit(db, habitId(), on)
          return printHabits
        }
        case "inc":
        case "dec": {
          const on = logDay(ctx)
          const by = rest[1] ? int(rest[1], "amount") : 1
          changing(ctx, `Logged ${quoted(store.habitName(db, habitId()))}`)
          store.bumpHabit(db, habitId(), on, verb === "inc" ? by : -by)
          return printHabits
        }
        case "set": {
          const on = logDay(ctx)
          changing(ctx, `Logged ${quoted(store.habitName(db, habitId()))}`)
          store.setHabitValue(db, habitId(), on, int(rest[1], "value"))
          return printHabits
        }
        case "skip": {
          const on = logDay(ctx)
          const start = addDays(on, -weekday(on))
          changing(ctx, `Skipped ${quoted(store.habitName(db, habitId()))}`)
          store.skipHabit(db, habitId(), on, start, addDays(start, 6))
          return printHabits
        }
        case "edit":
          changing(ctx, `Edited ${quoted(store.habitName(db, habitId()))}`)
          store.updateHabit(db, habitId(), {
            name: f.get("name"),
            target: f.has("target") ? int(f.get("target"), "target") : undefined,
            unit: f.get("unit"),
            days: weekdays(f.get("days")),
          })
          return printHabits
        case "up":
        case "down":
          changing(ctx, "Reordered habits")
          store.moveHabit(db, habitId(), verb === "up" ? -1 : 1)
          return printHabits
        case "rm":
          changing(ctx, `Deleted ${quoted(store.habitName(db, habitId()))}`)
          store.removeHabit(db, habitId())
          return printHabits
      }
      break
    }

    case "book":
    case "books": {
      const bookId = () => id(rest[0], "book")
      switch (verb) {
        case "":
        case "ls":
          return printBooks
        case "add":
          changing(ctx, `Added ${quoted(rest.join(" "))}`)
          store.addBook(db, rest.join(" "), int(f.get("pages"), "--pages"), today)
          return printBooks
        case "log": {
          const on = logDay(ctx)
          changing(ctx, `Logged pages in ${quoted(store.bookTitle(db, bookId()))}`)
          store.logReading(db, bookId(), int(rest[1], "pages"), on)
          return printBooks
        }
        case "edit":
          changing(ctx, `Edited ${quoted(store.bookTitle(db, bookId()))}`)
          store.updateBook(db, bookId(), {
            title: f.get("title"),
            totalPages: f.has("pages") ? int(f.get("pages"), "--pages") : undefined,
          })
          return printBooks
        case "rm":
          changing(ctx, `Deleted ${quoted(store.bookTitle(db, bookId()))}`)
          store.removeBook(db, bookId())
          return printBooks
      }
      break
    }

    case "event":
    case "events": {
      const eventId = () => id(rest[0], "event")
      switch (verb) {
        case "":
        case "ls":
          return printEvents
        case "add": {
          if (!f.has("on")) throw new LifeError("when is it? add --on <date>")
          const on = day(f.get("on")!, today)
          changing(ctx, `Added ${quoted(rest.join(" "))}`)
          store.addEvent(db, rest.join(" "), on, f.get("emoji") ?? "", today)
          return printEvents
        }
        case "edit": {
          const on = f.has("on") ? day(f.get("on")!, today) : undefined
          changing(ctx, `Edited ${quoted(store.eventTitle(db, eventId()))}`)
          store.updateEvent(db, eventId(), { title: f.get("title"), day: on, emoji: f.get("emoji") })
          return printEvents
        }
        case "rm":
          changing(ctx, `Deleted ${quoted(store.eventTitle(db, eventId()))}`)
          store.removeEvent(db, eventId())
          return printEvents
      }
      break
    }

    case "help":
      return () => console.log(HELP)
  }
  throw new LifeError(`unknown command "${words.join(" ")}" — try lifeos help`)
}

const HELP = `lifeos — tasks, habits, books and countdowns

  lifeos                              today at a glance
  lifeos add <task> [due:fri]         add a task
  lifeos quick "pay rent fri!"        add like the quick box: a date at the end, ! for a priority
  lifeos task done|undo|rm <n>        finish, reopen or delete a task
  lifeos task due <n> <date|none>     change a due date
  lifeos task rename <n> <title>
  lifeos task focus <n> [--off]       make it one of today's (max 3) priorities
  lifeos task drop <n>                decide against it

  lifeos plan                         today's priorities;  lifeos plan start  marks the day planned
  lifeos shutdown                     close the day (every due task needs a decision first)
  lifeos review                       this week and last: promises kept
  lifeos undo                         undo the last change

  lifeos habit add <name> [--kind check|count|avoid] [--target 8 --unit glasses] [--days mon,wed,fri]
  lifeos habit toggle <n>             mark done (check), full (count) or slipped (avoid)
  lifeos habit inc|dec <n> [amount]   count up or down
  lifeos habit skip <n>               skip today — once a week, keeps the streak
  lifeos habit edit <n> [--name] [--target] [--unit] [--days]
  lifeos habit rm <n>

  lifeos book add <title> --pages 320
  lifeos read <pages> [--book n]      log pages for today
  lifeos book edit <n> [--title] [--pages]
  lifeos book rm <n>

  lifeos event add <title> --on "nov 3" [--emoji ✈️]
  lifeos event edit <n> [--title] [--on] [--emoji]
  lifeos event rm <n>

  lifeos set [key value]              settings: strict, plan, morning, remind, shutdown, bedtime, notify
                                      e.g. lifeos set strict on · lifeos set shutdown 21:30

  --day <date>   log a habit or reading on another day (strict mode: yesterday at most)
  --json         print the full state as JSON
  dates: today, tomorrow, fri, next mon, in 3 days, 2w, 3.11, nov 3, 2026-11-03

  data:  ${paths.db}
  state: ${paths.state}`

function main() {
  // Nothing LifeOS creates — database, its journal files, the snapshot — is
  // for other users' eyes.
  process.umask(0o077)
  const json = process.argv.includes("--json")
  try {
    const args = parseArgs(process.argv.slice(2))
    if (args.flags.has("help")) {
      console.log(HELP)
      return
    }
    const db = openDb()
    const now = new Date()
    const ctx: Context = { db, today: todayDay(now), now, flags: args.flags, change: null, before: null, extra: {} }
    const print = run(ctx, args.words)
    if (ctx.change && ctx.before) saveSnapshot(ctx.before, ctx.change)
    const state = buildState(db, ctx.today, now)
    state.change = ctx.change ? { label: ctx.change, at: now.toISOString() } : null
    if (args.words[0] === "tick") tick(db, state, now)
    if (args.words[0] !== "parse") writeState(state)
    db.close()
    if (json) console.log(JSON.stringify(args.words[0] === "parse" ? { parsed: ctx.extra.parsed ?? null } : { ...state, ...ctx.extra }))
    else if (args.words[0] === "state") console.log(JSON.stringify(state))
    else print(state)
  } catch (error) {
    const message = error instanceof LifeError ? error.message : error instanceof Error ? error.message : String(error)
    if (json) console.log(JSON.stringify({ error: message }))
    else console.error(`lifeos: ${message}`)
    process.exit(1)
  }
}

main()
