import { describe, expect, test } from "bun:test"
import { addDays, diffDays, parseDay, parseWeekdays, weekday } from "../src/dates"
import { openDb } from "../src/db"
import { buildState, FIRE_STREAK, HEAT_WEEKS } from "../src/state"
import * as store from "../src/store"

// 2026-09-25 is a Friday.
const FRI = "2026-09-25"

describe("dates", () => {
  test("relative words", () => {
    expect(parseDay("today", FRI)).toBe(FRI)
    expect(parseDay("tomorrow", FRI)).toBe("2026-09-26")
    expect(parseDay("tmr", FRI)).toBe("2026-09-26")
    expect(parseDay("in 3 days", FRI)).toBe("2026-09-28")
    expect(parseDay("2w", FRI)).toBe("2026-10-09")
    expect(parseDay("+1", FRI)).toBe("2026-09-26")
  })

  test("weekdays: the coming one, today included; next skips today", () => {
    expect(parseDay("fri", FRI)).toBe(FRI)
    expect(parseDay("next fri", FRI)).toBe("2026-10-02")
    expect(parseDay("mon", FRI)).toBe("2026-09-28")
    expect(parseDay("thursday", FRI)).toBe("2026-10-01")
    expect(parseDay("t", FRI)).toBeNull()
  })

  test("calendar dates roll into next year once passed", () => {
    expect(parseDay("nov 3", FRI)).toBe("2026-11-03")
    expect(parseDay("3 november", FRI)).toBe("2026-11-03")
    expect(parseDay("3.11", FRI)).toBe("2026-11-03")
    expect(parseDay("jan 5", FRI)).toBe("2027-01-05")
    expect(parseDay("03.11.2026", FRI)).toBe("2026-11-03")
    expect(parseDay("2026-02-30", FRI)).toBeNull()
    expect(parseDay("31.02", FRI)).toBeNull()
    expect(parseDay("banana", FRI)).toBeNull()
  })

  test("day math", () => {
    expect(diffDays(FRI, "2026-11-03")).toBe(39)
    expect(addDays("2026-12-31", 1)).toBe("2027-01-01")
    expect(weekday(FRI)).toBe(4)
    expect(parseWeekdays("mon,wed,fri")).toBe(0b0010101)
    expect(parseWeekdays("weekdays")).toBe(0b0011111)
    expect(parseWeekdays("funday")).toBeNull()
  })
})

function fresh() {
  return openDb(":memory:")
}

describe("tasks", () => {
  test("bucket by due date", () => {
    const db = fresh()
    store.addTask(db, "late", addDays(FRI, -2), FRI)
    store.addTask(db, "now", FRI, FRI)
    store.addTask(db, "soon", addDays(FRI, 3), FRI)
    const someday = store.addTask(db, "someday", null, FRI)
    store.setTaskDone(db, someday, true, FRI)

    const s = buildState(db, FRI)
    expect(s.tasks.overdue.map((t) => t.title)).toEqual(["late"])
    expect(s.tasks.today.map((t) => t.title)).toEqual(["now"])
    expect(s.tasks.upcoming.map((t) => t.title)).toEqual(["soon"])
    expect(s.tasks.doneToday.map((t) => t.title)).toEqual(["someday"])
    expect(s.summary.tasksLeft).toBe(2)

    // Finished yesterday: gone from today's view.
    expect(buildState(db, addDays(FRI, 1)).tasks.doneToday).toHaveLength(0)
  })

  test("empty titles are refused", () => {
    expect(() => store.addTask(fresh(), "   ", null, FRI)).toThrow()
  })
})

describe("habits", () => {
  test("streak ignores an unfinished today and catches fire", () => {
    const db = fresh()
    const h = store.addHabit(db, { name: "Meditate", kind: "check" }, addDays(FRI, -10))
    for (let i = 1; i <= FIRE_STREAK; i++) store.toggleHabit(db, h, addDays(FRI, -i))

    let habit = buildState(db, FRI).habits[0]!
    expect(habit.streak).toBe(FIRE_STREAK)
    expect(habit.onFire).toBe(true)
    expect(habit.done).toBe(false)

    store.toggleHabit(db, h, FRI)
    habit = buildState(db, FRI).habits[0]!
    expect(habit.streak).toBe(FIRE_STREAK + 1)

    // A missed yesterday breaks it.
    expect(buildState(db, addDays(FRI, 2)).habits[0]!.streak).toBe(0)
  })

  test("rest days neither count nor break the streak", () => {
    const db = fresh()
    // Mon/Wed/Fri. FRI-2 = Wed, FRI-4 = Mon.
    const h = store.addHabit(db, { name: "Gym", kind: "check", days: 0b0010101 }, addDays(FRI, -14))
    store.toggleHabit(db, h, addDays(FRI, -4))
    store.toggleHabit(db, h, addDays(FRI, -2))
    store.toggleHabit(db, h, FRI)
    const habit = buildState(db, FRI).habits[0]!
    expect(habit.streak).toBe(3)
    const cells = habit.heat.flat()
    expect(cells.find((c) => c.day === addDays(FRI, -1))!.state).toBe("off")
    expect(cells.find((c) => c.day === FRI)!.state).toBe("done")
  })

  test("count habits fill up and grade the heatmap", () => {
    const db = fresh()
    const h = store.addHabit(db, { name: "Water", kind: "count", target: 8, unit: "glasses" }, FRI)
    store.bumpHabit(db, h, FRI, 3)
    let habit = buildState(db, FRI).habits[0]!
    expect(habit.value).toBe(3)
    expect(habit.done).toBe(false)
    expect(habit.heat.flat().find((c) => c.day === FRI)!.level).toBe(2)

    store.bumpHabit(db, h, FRI, 5)
    habit = buildState(db, FRI).habits[0]!
    expect(habit.done).toBe(true)
    expect(habit.progress).toBe(1)

    store.bumpHabit(db, h, FRI, -20)
    expect(buildState(db, FRI).habits[0]!.value).toBe(0)
  })

  test("avoid habits count clean days and reset on a slip", () => {
    const db = fresh()
    const h = store.addHabit(db, { name: "No sugar", kind: "avoid" }, addDays(FRI, -4))
    expect(buildState(db, FRI).habits[0]!.streak).toBe(5)
    store.toggleHabit(db, h, addDays(FRI, -1))
    const habit = buildState(db, FRI).habits[0]!
    expect(habit.streak).toBe(1)
    expect(habit.heat.flat().find((c) => c.day === addDays(FRI, -1))!.state).toBe("slip")
  })

  test("heatmap is whole Monday-first weeks ending this week", () => {
    const db = fresh()
    store.addHabit(db, { name: "Read", kind: "check" }, FRI)
    const heat = buildState(db, FRI).habits[0]!.heat
    expect(heat).toHaveLength(HEAT_WEEKS)
    expect(heat.every((w) => w.length === 7)).toBe(true)
    expect(weekday(heat[0]![0]!.day)).toBe(0)
    const last = heat[HEAT_WEEKS - 1]!
    expect(last[4]!.day).toBe(FRI)
    expect(last[5]!.state).toBe("future")
  })
})

describe("books", () => {
  test("logs add up, pace and finish date follow", () => {
    const db = fresh()
    const b = store.addBook(db, "Dune", 100, addDays(FRI, -3))
    store.logReading(db, b, 10, addDays(FRI, -3))
    store.logReading(db, b, 10, addDays(FRI, -2))
    store.logReading(db, b, 5, FRI)
    store.logReading(db, b, 5, FRI)

    const book = buildState(db, FRI).books.reading[0]!
    expect(book.read).toBe(30)
    expect(book.today).toBe(10)
    expect(book.pace).toBe(7.5) // 30 pages over 4 days
    expect(book.etaDays).toBe(10) // 70 left
    expect(book.recent).toHaveLength(14)
  })

  test("the last page finishes the book and caps the log", () => {
    const db = fresh()
    const b = store.addBook(db, "Short", 50, FRI)
    store.logReading(db, b, 80, FRI)
    const s = buildState(db, FRI)
    expect(s.books.reading).toHaveLength(0)
    expect(s.books.finished[0]!.read).toBe(50)
    expect(s.books.finished[0]!.finishedOn).toBe(FRI)
    expect(() => store.logReading(db, b, 5, FRI)).toThrow()

    // Correcting downwards re-opens it.
    store.logReading(db, b, -10, FRI)
    expect(buildState(db, FRI).books.reading[0]!.read).toBe(40)
  })

  test("`read` goes to the book touched last", () => {
    const db = fresh()
    const a = store.addBook(db, "A", 300, addDays(FRI, -5))
    store.addBook(db, "B", 300, addDays(FRI, -4))
    store.logReading(db, a, 10, FRI)
    expect(store.currentBookId(db)).toBe(a)
  })
})

describe("events", () => {
  test("count down and vanish once past", () => {
    const db = fresh()
    store.addEvent(db, "Trip", "2026-11-03", "✈️", FRI)
    store.addEvent(db, "Yesterday", addDays(FRI, -1), "", addDays(FRI, -5))
    store.addEvent(db, "Tonight", FRI, "🎉", addDays(FRI, -4))
    const s = buildState(db, FRI)
    expect(s.events.map((e) => e.title)).toEqual(["Tonight", "Trip"])
    expect(s.events[0]!.daysLeft).toBe(0)
    expect(s.events[0]!.progress).toBe(1)
    expect(s.events[1]!.daysLeft).toBe(39)
    expect(s.summary.nextEvent!.title).toBe("Tonight")
  })
})

describe("backfill", () => {
  test("logging before a habit existed moves its start back", () => {
    const db = fresh()
    const h = store.addHabit(db, { name: "Walk", kind: "check" }, FRI)
    for (let i = 1; i <= 3; i++) store.toggleHabit(db, h, addDays(FRI, -i))
    const habit = buildState(db, FRI).habits[0]!
    expect(habit.streak).toBe(3)
    expect(habit.heat.flat().find((c) => c.day === addDays(FRI, -3))!.state).toBe("done")
  })
})

describe("privacy", () => {
  test("data and state are readable by their owner only, even under a loose umask", () => {
    const { mkdtempSync, statSync, mkdirSync, writeFileSync, chmodSync } = require("node:fs") as typeof import("node:fs")
    const { join } = require("node:path") as typeof import("node:path")
    const { tmpdir } = require("node:os") as typeof import("node:os")
    const { writeState } = require("../src/state") as typeof import("../src/state")

    const previous = process.umask(0o022)
    try {
      const root = mkdtempSync(join(tmpdir(), "lifeos-"))
      // A directory and file left world-readable by an older version get tightened.
      const dataDir = join(root, "share/lifeos")
      mkdirSync(dataDir, { recursive: true, mode: 0o755 })
      const dbPath = join(dataDir, "lifeos.db")
      writeFileSync(dbPath, "")
      chmodSync(dbPath, 0o644)

      const db = openDb(dbPath)
      store.addTask(db, "secret", null, FRI)
      const statePath = join(root, "state/lifeos/state.json")
      writeState(buildState(db, FRI), statePath)
      db.close()

      const mode = (p: string) => statSync(p).mode & 0o777
      expect(mode(dataDir)).toBe(0o700)
      expect(mode(dbPath)).toBe(0o600)
      expect(mode(join(root, "state/lifeos"))).toBe(0o700)
      expect(mode(statePath)).toBe(0o600)
    } finally {
      process.umask(previous)
    }
  })
})
