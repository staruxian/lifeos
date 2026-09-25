#!/usr/bin/env bun
import type { Database } from "bun:sqlite"
import { parseDay, parseWeekdays, today as todayDay, type Day } from "./dates"
import { openDb, paths } from "./db"
import { buildState, writeState, type State } from "./state"
import * as store from "./store"
import { LifeError, type HabitKind } from "./store"
import { printOverview, printBooks, printEvents, printHabits, printTasks } from "./print"

const BOOLEAN_FLAGS = new Set(["json", "help"])

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

type Printer = (state: State) => void

// Returns what to print once the change is saved.
function run(db: Database, args: Args, today: Day): Printer {
  const [group = "", verb = "", ...rest] = args.words
  const f = args.flags
  const on = f.has("day") ? day(f.get("day")!, today) : today

  switch (group) {
    case "":
    case "today":
      return printOverview
    case "state":
      return () => {}

    case "add":
      return run(db, { words: ["task", "add", ...args.words.slice(1)], flags: f }, today)
    case "read":
      return run(db, { words: ["book", "log", f.get("book") ?? String(store.currentBookId(db)), ...args.words.slice(1)], flags: f }, today)

    case "task":
    case "tasks":
      switch (verb) {
        case "":
        case "ls":
          return printTasks
        case "add": {
          const { title, due } = splitDue(rest)
          store.addTask(db, title, optionalDay(f.get("due") ?? due, today), today)
          return printTasks
        }
        case "done":
          store.setTaskDone(db, id(rest[0], "task"), true, today)
          return printTasks
        case "undo":
          store.setTaskDone(db, id(rest[0], "task"), false, today)
          return printTasks
        case "toggle":
          store.toggleTask(db, id(rest[0], "task"), today)
          return printTasks
        case "due":
          store.setTaskDue(db, id(rest[0], "task"), optionalDay(rest.slice(1).join(" ") || "none", today))
          return printTasks
        case "rename":
          store.renameTask(db, id(rest[0], "task"), rest.slice(1).join(" "))
          return printTasks
        case "rm":
          store.removeTask(db, id(rest[0], "task"))
          return printTasks
      }
      break

    case "habit":
    case "habits":
      switch (verb) {
        case "":
        case "ls":
          return printHabits
        case "add":
          store.addHabit(db, {
            name: rest.join(" "),
            kind: kind(f.get("kind")),
            target: f.has("target") ? int(f.get("target"), "target") : undefined,
            unit: f.get("unit"),
            days: weekdays(f.get("days")),
          }, today)
          return printHabits
        case "toggle":
          store.toggleHabit(db, id(rest[0], "habit"), on)
          return printHabits
        case "inc":
          store.bumpHabit(db, id(rest[0], "habit"), on, rest[1] ? int(rest[1], "amount") : 1)
          return printHabits
        case "dec":
          store.bumpHabit(db, id(rest[0], "habit"), on, -(rest[1] ? int(rest[1], "amount") : 1))
          return printHabits
        case "set":
          store.setHabitValue(db, id(rest[0], "habit"), on, int(rest[1], "value"))
          return printHabits
        case "edit":
          store.updateHabit(db, id(rest[0], "habit"), {
            name: f.get("name"),
            target: f.has("target") ? int(f.get("target"), "target") : undefined,
            unit: f.get("unit"),
            days: weekdays(f.get("days")),
          })
          return printHabits
        case "up":
        case "down":
          store.moveHabit(db, id(rest[0], "habit"), verb === "up" ? -1 : 1)
          return printHabits
        case "rm":
          store.removeHabit(db, id(rest[0], "habit"))
          return printHabits
      }
      break

    case "book":
    case "books":
      switch (verb) {
        case "":
        case "ls":
          return printBooks
        case "add":
          store.addBook(db, rest.join(" "), int(f.get("pages"), "--pages"), today)
          return printBooks
        case "log":
          store.logReading(db, id(rest[0], "book"), int(rest[1], "pages"), on)
          return printBooks
        case "edit":
          store.updateBook(db, id(rest[0], "book"), {
            title: f.get("title"),
            totalPages: f.has("pages") ? int(f.get("pages"), "--pages") : undefined,
          })
          return printBooks
        case "rm":
          store.removeBook(db, id(rest[0], "book"))
          return printBooks
      }
      break

    case "event":
    case "events":
      switch (verb) {
        case "":
        case "ls":
          return printEvents
        case "add": {
          if (!f.has("on")) throw new LifeError("when is it? add --on <date>")
          store.addEvent(db, rest.join(" "), day(f.get("on")!, today), f.get("emoji") ?? "", today)
          return printEvents
        }
        case "edit":
          store.updateEvent(db, id(rest[0], "event"), {
            title: f.get("title"),
            day: f.has("on") ? day(f.get("on")!, today) : undefined,
            emoji: f.get("emoji"),
          })
          return printEvents
        case "rm":
          store.removeEvent(db, id(rest[0], "event"))
          return printEvents
      }
      break

    case "help":
      return () => console.log(HELP)
  }
  throw new LifeError(`unknown command "${args.words.join(" ")}" — try lifeos help`)
}

const HELP = `lifeos — tasks, habits, books and countdowns

  lifeos                              today at a glance
  lifeos add <task> [due:fri]         add a task
  lifeos task done|undo|rm <n>        finish, reopen or delete a task
  lifeos task due <n> <date|none>     change a due date

  lifeos habit add <name> [--kind check|count|avoid] [--target 8 --unit glasses] [--days mon,wed,fri]
  lifeos habit toggle <n>             mark done (check), full (count) or slipped (avoid)
  lifeos habit inc|dec <n> [amount]   count up or down
  lifeos habit rm <n>

  lifeos book add <title> --pages 320
  lifeos read <pages> [--book n]      log pages for today
  lifeos book rm <n>

  lifeos event add <title> --on "nov 3" [--emoji ✈️]
  lifeos event rm <n>

  --day <date>   log a habit or reading on another day
  --json         print the full state as JSON
  dates: today, tomorrow, fri, next mon, in 3 days, 2w, 3.11, nov 3, 2026-11-03

  data:  ${paths.db}
  state: ${paths.state}`

function main() {
  // Nothing LifeOS creates — database, its journal files, the snapshot — is
  // for other users' eyes.
  process.umask(0o077)
  let args: Args
  const json = process.argv.includes("--json")
  try {
    args = parseArgs(process.argv.slice(2))
    if (args.flags.has("help")) {
      console.log(HELP)
      return
    }
    const db = openDb()
    const today = todayDay()
    const print = run(db, args, today)
    const state = buildState(db, today)
    writeState(state)
    db.close()
    if (json || args.words[0] === "state") console.log(JSON.stringify(state))
    else print(state)
  } catch (error) {
    const message = error instanceof LifeError ? error.message : error instanceof Error ? error.message : String(error)
    if (json) console.log(JSON.stringify({ error: message }))
    else console.error(`lifeos: ${message}`)
    process.exit(1)
  }
}

main()
