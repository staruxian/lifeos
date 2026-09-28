import { describe, expect, test } from "bun:test"
import { mkdtempSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Database } from "bun:sqlite"
import { addDays, nextBirthday, parseBirthday } from "../src/dates"
import { openDb } from "../src/db"
import { dueNotes } from "../src/notify"
import { buildState } from "../src/state"
import * as store from "../src/store"
import { saveSnapshot, undo } from "../src/undo"

const FRI = "2026-09-25"
const at = (time: string, day = FRI) => new Date(`${day}T${time}:00`)
const fresh = () => openDb(":memory:")

describe("birthdays", () => {
  test("parse the ways people write them", () => {
    expect(parseBirthday("12.10.2001")).toEqual({ month: 10, day: 12, year: 2001 })
    expect(parseBirthday("12.10")).toEqual({ month: 10, day: 12, year: null })
    expect(parseBirthday("oct 12")).toEqual({ month: 10, day: 12, year: null })
    expect(parseBirthday("12 October 1998")).toEqual({ month: 10, day: 12, year: 1998 })
    expect(parseBirthday("2001-10-12")).toEqual({ month: 10, day: 12, year: 2001 })
    expect(parseBirthday("29.02")).toEqual({ month: 2, day: 29, year: null })
    expect(parseBirthday("31.02")).toBeNull()
    expect(parseBirthday("12.10.2090")).toBeNull() // not born yet
    expect(parseBirthday("soon")).toBeNull()
  })

  test("next birthday, today included; Feb 29 on Feb 28 in common years", () => {
    expect(nextBirthday({ month: 9, day: 25, year: null }, FRI)).toBe(FRI)
    expect(nextBirthday({ month: 9, day: 24, year: null }, FRI)).toBe("2027-09-24")
    expect(nextBirthday({ month: 2, day: 29, year: null }, FRI)).toBe("2027-02-28")
  })

  test("people know the age they turn, and stay out of the events", () => {
    const db = fresh()
    store.addPerson(db, "Aziz", { month: 10, day: 12, year: 2001 }, FRI)
    store.addPerson(db, "Mom", { month: 9, day: 26, year: null }, FRI)
    store.addEvent(db, "Trip", "2026-10-01", "✈️", FRI)

    const s = buildState(db, FRI, at("09:00"))
    expect(s.people.map((p) => p.name)).toEqual(["Mom", "Aziz"])
    expect(s.people[1]!.turning).toBe(25)
    expect(s.people[0]!.turning).toBeNull()
    expect(s.events.map((e) => e.title)).toEqual(["Trip"])
    expect(s.summary.nextEvent!.title).toBe("Trip")
    expect(s.summary.nextBirthday!.name).toBe("Mom")
  })

  test("a birthday notifies a week, a day, and on the day", () => {
    const db = fresh()
    store.addPerson(db, "Aziz", { month: 9, day: 26, year: 2001 }, FRI)
    const note = dueNotes(buildState(db, FRI, at("09:00")), at("09:00")).find((n) => n.key.startsWith("birthday:"))
    expect(note!.title).toBe("🎂 Aziz turns 25 tomorrow")
  })
})

describe("habit reminders", () => {
  test("its own time, once, only while open", () => {
    const db = fresh()
    const h = store.addHabit(db, { name: "Gym", kind: "check" }, FRI)
    store.setHabitReminder(db, h, "18:00")
    expect(dueNotes(buildState(db, FRI, at("17:59")), at("17:59")).some((n) => n.key.startsWith("habit:"))).toBe(false)
    expect(dueNotes(buildState(db, FRI, at("18:00")), at("18:00")).some((n) => n.key === `habit:${h}:${FRI}`)).toBe(true)
    store.toggleHabit(db, h, FRI)
    expect(dueNotes(buildState(db, FRI, at("18:30")), at("18:30")).some((n) => n.key.startsWith("habit:"))).toBe(false)
    expect(buildState(db, FRI, at("18:30")).habits[0]!.remindAt).toBe("18:00")
  })
})

describe("check-in and insights", () => {
  test("the day's rating and note are kept", () => {
    const db = fresh()
    store.checkIn(db, FRI, 4, "  good   focus day ")
    const s = buildState(db, FRI, at("21:00"))
    expect(s.day.mood).toBe(4)
    expect(s.day.note).toBe("good focus day")
    expect(s.insights.mood.at(-1)).toEqual({ day: FRI, mood: 4, note: "good focus day" })
    expect(() => store.checkIn(db, FRI, 6, "")).toThrow()
  })

  test("finds the weekday pattern and the longest run", () => {
    const db = fresh()
    const start = addDays(FRI, -83)
    const h = store.addHabit(db, { name: "Read", kind: "check" }, start)
    // Kept every day except Saturdays and Sundays.
    for (let day = start; day < FRI; day = addDays(day, 1)) {
      const dow = new Date(day + "T12:00:00").getDay()
      if (dow !== 0 && dow !== 6) store.toggleHabit(db, h, day)
    }
    const i = buildState(db, FRI, at("12:00")).insights
    expect(i.lines.some((l) => /best on Mondays .*slip most on (Saturdays|Sundays)/.test(l.text))).toBe(true)
    expect(i.records[0]!.best).toBe(5)
    expect(i.weekdays[0]!.rate).toBe(1)
    expect(i.weekdays[6]!.rate).toBe(0)
  })

  test("quiet with little data", () => {
    const db = fresh()
    store.addHabit(db, { name: "Read", kind: "check" }, FRI)
    expect(buildState(db, FRI, at("12:00")).insights.lines).toHaveLength(0)
  })
})

describe("undo across an upgrade", () => {
  test("a copy from an older schema is refused, not half-restored", () => {
    const dir = mkdtempSync(join(tmpdir(), "lifeos-old-"))
    const old = new Database(join(dir, "old.db"))
    old.exec("CREATE TABLE tasks (id INTEGER); PRAGMA user_version = 1;")
    const bytes = old.serialize()
    old.close()
    saveSnapshot(bytes, "old change", join(dir, "undo.db"))

    const db = openDb(join(dir, "now.db"))
    store.addTask(db, "keep", null, FRI)
    expect(() => undo(db, join(dir, "undo.db"))).toThrow(/nothing to undo/)
    expect(buildState(db, FRI, at("12:00")).tasks.someday).toHaveLength(1)
  })
})
