import { describe, expect, test } from "bun:test"
import { mkdtempSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { addDays } from "../src/dates"
import { openDb } from "../src/db"
import { dueNotes, tick, type Note } from "../src/notify"
import { parseQuick } from "../src/quick"
import { writeSetting } from "../src/settings"
import { buildState, buildWeek } from "../src/state"
import * as store from "../src/store"
import { capture, lastChange, saveSnapshot, undo } from "../src/undo"

// 2026-09-25 is a Friday; the week runs Mon 21 – Sun 27.
const FRI = "2026-09-25"
const MON = "2026-09-21"
const at = (time: string) => new Date(`${FRI}T${time}:00`)
const fresh = () => openDb(":memory:")

describe("priorities and the plan", () => {
  test("at most three, and they land on today", () => {
    const db = fresh()
    const ids = [1, 2, 3, 4].map((n) => store.addTask(db, `t${n}`, n === 1 ? addDays(FRI, 5) : null, FRI))
    for (const id of ids.slice(0, 3)) store.setFocus(db, id, true, FRI)
    expect(() => store.setFocus(db, ids[3]!, true, FRI)).toThrow(/3 priorities/)

    const s = buildState(db, FRI, at("09:00"))
    expect(s.day.priorities.map((t) => t.title)).toEqual(["t1", "t2", "t3"])
    expect(s.tasks.today.every((t) => t.focus)).toBe(true) // pulled forward to today
    expect(s.summary.priorities).toBe(3)

    // Tomorrow they are ordinary tasks again.
    expect(buildState(db, addDays(FRI, 1), at("09:00")).day.priorities).toHaveLength(0)
  })

  test("needs a plan in the morning until planned", () => {
    const db = fresh()
    expect(buildState(db, FRI, at("03:00")).day.needsPlan).toBe(false)
    expect(buildState(db, FRI, at("08:30")).day.needsPlan).toBe(true)
    store.markPlanned(db, FRI, at("08:31").toISOString())
    expect(buildState(db, FRI, at("08:32")).day.needsPlan).toBe(false)
    writeSetting(db, "plan", "off")
    expect(buildState(db, addDays(FRI, 1), at("09:00")).day.needsPlan).toBe(false)
  })

  test("shutdown wants every due task decided", () => {
    const db = fresh()
    const late = store.addTask(db, "late", addDays(FRI, -1), FRI)
    const now = store.addTask(db, "now", FRI, FRI)
    store.addTask(db, "later", addDays(FRI, 2), FRI)

    let s = buildState(db, FRI, at("21:30"))
    expect(s.day.needsShutdown).toBe(true)
    expect(s.day.leftovers.map((t) => t.title)).toEqual(["late", "now"])
    expect(() => store.markShutdown(db, FRI, "x")).toThrow(/2 tasks still need/)

    store.setTaskDue(db, late, addDays(FRI, 1))
    store.dropTask(db, now, FRI)
    store.markShutdown(db, FRI, "x")
    s = buildState(db, FRI, at("21:31"))
    expect(s.day.shutdown).toBe(true)
    expect(s.day.needsShutdown).toBe(false)
    expect(s.tasks.today).toHaveLength(0) // dropped is gone
  })
})

describe("skips", () => {
  test("once a week, keeps the streak, counts as neither", () => {
    const db = fresh()
    const h = store.addHabit(db, { name: "Run", kind: "check" }, addDays(FRI, -6))
    for (const d of [-4, -3, -1]) store.toggleHabit(db, h, addDays(FRI, d))
    store.skipHabit(db, h, addDays(FRI, -2), MON, addDays(MON, 6))
    store.toggleHabit(db, h, FRI)

    const habit = buildState(db, FRI, at("12:00")).habits[0]!
    expect(habit.streak).toBe(4) // the skip did not break it, nor count
    expect(habit.canSkip).toBe(false)
    expect(habit.heat.flat().find((c) => c.day === addDays(FRI, -2))!.state).toBe("skip")
    expect(() => store.skipHabit(db, h, FRI, MON, addDays(MON, 6))).toThrow(/one skip a week/)

    const avoid = store.addHabit(db, { name: "No sugar", kind: "avoid" }, FRI)
    expect(() => store.skipHabit(db, avoid, FRI, MON, addDays(MON, 6))).toThrow()
  })

  test("a skipped habit is not due today", () => {
    const db = fresh()
    const h = store.addHabit(db, { name: "Run", kind: "check" }, FRI)
    store.addHabit(db, { name: "Read", kind: "check" }, FRI)
    store.skipHabit(db, h, FRI, MON, addDays(MON, 6))
    const s = buildState(db, FRI, at("12:00"))
    expect(s.summary.habitsDue).toBe(1)
    expect(s.habits[0]!.skipped).toBe(true)
  })
})

describe("alerts grow louder", () => {
  test("none, warn two hours after the reminder, urgent an hour before bed", () => {
    const db = fresh()
    store.addHabit(db, { name: "Read", kind: "check" }, FRI)
    expect(buildState(db, FRI, at("20:30")).day.alert).toBe("none")
    expect(buildState(db, FRI, at("22:00")).day.alert).toBe("urgent") // remind 20:00 +2h = 22:00, bedtime 23:00 -1h = 22:00
    writeSetting(db, "bedtime", "23:59")
    expect(buildState(db, FRI, at("22:10")).day.alert).toBe("warn")
    expect(buildState(db, FRI, at("23:00")).day.alert).toBe("urgent")
  })
})

describe("weekly score", () => {
  test("promises kept across habits and priorities", () => {
    const db = fresh()
    const h = store.addHabit(db, { name: "Read", kind: "check" }, addDays(MON, -7))
    const g = store.addHabit(db, { name: "Gym", kind: "check", days: 0b0010101 }, addDays(MON, -7))
    for (let i = 0; i < 7; i++) store.toggleHabit(db, h, addDays(MON, -7 + i)) // last week: all 7
    store.toggleHabit(db, g, addDays(MON, -7)) // Gym: 1 of 3 (Mon, Wed, Fri)
    const w = buildWeek(db, addDays(MON, -7), addDays(MON, -1), FRI)
    expect(w.due).toBe(10)
    expect(w.kept).toBe(8)
    expect(w.perfectDays).toBe(5) // Mon + the 4 days without Gym
    expect(w.best!.name).toBe("Read")
    expect(w.worst!.name).toBe("Gym")

    const s = buildState(db, FRI, at("09:00"))
    expect(s.review.due).toBe(true)
    db.query("INSERT INTO settings (key, value) VALUES ('reviewed', ?)").run(addDays(MON, -7))
    expect(buildState(db, FRI, at("09:00")).review.due).toBe(false)
  })
})

describe("strict mode and settings", () => {
  test("settings validate", () => {
    const db = fresh()
    writeSetting(db, "shutdown", "9:30")
    writeSetting(db, "strict", "yes")
    const s = buildState(db, FRI, at("09:00")).settings
    expect(s.shutdown).toBe("09:30")
    expect(s.strict).toBe("on")
    expect(() => writeSetting(db, "shutdown", "25:00")).toThrow()
    expect(() => writeSetting(db, "volume", "11")).toThrow()
  })
})

describe("undo", () => {
  test("puts every table back as it was", () => {
    const dir = mkdtempSync(join(tmpdir(), "lifeos-undo-"))
    const path = join(dir, "undo.db")
    const db = openDb(join(dir, "lifeos.db"))
    const t = store.addTask(db, "keep me", null, FRI)
    const before = capture(db)
    store.removeTask(db, t)
    store.addHabit(db, { name: "new", kind: "check" }, FRI)
    saveSnapshot(before, "Deleted “keep me”", path)

    expect(lastChange(path)!.label).toBe("Deleted “keep me”")
    undo(db, path)
    const s = buildState(db, FRI, at("09:00"))
    expect(s.tasks.someday.map((x) => x.title)).toEqual(["keep me"])
    expect(s.habits).toHaveLength(0)
    expect(() => undo(db, path)).toThrow(/nothing to undo/)
  })
})

describe("quick add", () => {
  test("reads dates off the end and ! as a priority", () => {
    expect(parseQuick("pay rent fri", FRI)).toEqual({ kind: "task", title: "pay rent", due: FRI, focus: false })
    expect(parseQuick("call mom next mon", FRI)).toEqual({ kind: "task", title: "call mom", due: "2026-09-28", focus: false })
    expect(parseQuick("renew passport on nov 3", FRI)).toEqual({ kind: "task", title: "renew passport", due: "2026-11-03", focus: false })
    expect(parseQuick("book dentist in 3 days", FRI)).toEqual({ kind: "task", title: "book dentist", due: "2026-09-28", focus: false })
    expect(parseQuick("ship it!", FRI)).toEqual({ kind: "task", title: "ship it", due: FRI, focus: true })
    expect(parseQuick("what do we", FRI)).toEqual({ kind: "task", title: "what do we", due: null, focus: false })
    expect(parseQuick("buy 2 apples", FRI)).toEqual({ kind: "task", title: "buy 2 apples", due: null, focus: false })
    expect(parseQuick("tomorrow", FRI)).toEqual({ kind: "task", title: "tomorrow", due: null, focus: false })
    expect(parseQuick("read 20", FRI)).toEqual({ kind: "read", pages: 20 })
    expect(parseQuick("   ", FRI)).toBeNull()
  })
})

describe("notifications", () => {
  test("each fires once; habit reminders collapse to the loudest", () => {
    const db = fresh()
    store.addHabit(db, { name: "Read", kind: "check" }, FRI)
    store.addTask(db, "late", FRI, FRI)
    store.addEvent(db, "Trip", addDays(FRI, 3), "✈️", FRI)
    const sent: Note[] = []
    const send = (n: Note) => sent.push(n)

    tick(db, buildState(db, FRI, at("08:05")), at("08:05"), send)
    expect(sent.map((n) => n.key)).toEqual([`plan:${FRI}`, expect.stringMatching(/^event:/)])

    // Booting late: remind + shutdown + bedtime are all due; the habit ones collapse.
    tick(db, buildState(db, FRI, at("22:30")), at("22:30"), send)
    expect(sent.slice(2).map((n) => n.key.split(":")[0])).toEqual(["shutdown", "bedtime"])
    expect(sent.at(-1)!.urgent).toBe(true)

    const count = sent.length
    tick(db, buildState(db, FRI, at("22:31")), at("22:31"), send)
    expect(sent.length).toBe(count)
  })

  test("quiet when turned off", () => {
    const db = fresh()
    store.addHabit(db, { name: "Read", kind: "check" }, FRI)
    writeSetting(db, "notify", "off")
    expect(dueNotes(buildState(db, FRI, at("22:30")), at("22:30"))).toHaveLength(0)
  })
})
