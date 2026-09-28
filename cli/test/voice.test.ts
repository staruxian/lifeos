import { describe, expect, test } from "bun:test"
import { addDays } from "../src/dates"
import { openDb } from "../src/db"
import { dueNotes, tick, type Note } from "../src/notify"
import { writeSetting } from "../src/settings"
import { buildState, flameTier } from "../src/state"
import * as store from "../src/store"
import { habitLine, topicOf } from "../src/voice"

const FRI = "2026-09-25"
const at = (time: string) => new Date(`${FRI}T${time}:00`)
const fresh = () => openDb(":memory:")

describe("voice", () => {
  test("habits get lines about what they are", () => {
    expect(topicOf("Gym")).toBe("fitness")
    expect(topicOf("30 push ups")).toBe("fitness")
    expect(topicOf("Read 20 pages")).toBe("reading")
    expect(topicOf("Drink water")).toBe("water")
    expect(topicOf("Meditate")).toBe("mind")
    expect(topicOf("AS Math prep")).toBe("study")
    expect(topicOf("Call grandma")).toBe("general")
  })

  test("the same key keeps its words; the tone changes them", () => {
    const a = habitLine("savage", "habit:1:2026-09-25", "Gym")
    expect(habitLine("savage", "habit:1:2026-09-25", "Gym")).toBe(a)
    expect(habitLine("gentle", "habit:1:2026-09-25", "Gym")).not.toBe(a)
    // Across a week of days, savage gym lines vary.
    const week = new Set(Array.from({ length: 7 }, (_, i) => habitLine("savage", `habit:1:${addDays(FRI, i)}`, "Gym")))
    expect(week.size).toBeGreaterThan(2)
  })

  test("savage gym reminders roast you", () => {
    const db = fresh()
    const h = store.addHabit(db, { name: "Gym", kind: "check" }, FRI)
    store.setHabitReminder(db, h, "18:00")
    writeSetting(db, "tone", "savage")
    const note = dueNotes(buildState(db, FRI, at("18:00")), at("18:00")).find((n) => n.key.startsWith("habit:"))!
    expect(note.title).toBe("Gym")
    expect(note.body).not.toMatch(/\{\w+\}/) // every placeholder filled
    expect(() => writeSetting(db, "tone", "rude")).toThrow(/gentle, coach or savage/)
  })
})

describe("savage nags until it's done", () => {
  test("a new reminder every 45 minutes, five at most, gone once done", () => {
    const db = fresh()
    const h = store.addHabit(db, { name: "Gym", kind: "check" }, FRI)
    store.setHabitReminder(db, h, "18:00")
    writeSetting(db, "tone", "savage")
    writeSetting(db, "remind", "23:00") // keep the general reminder out of the way
    const sent: Note[] = []
    const send = (n: Note) => sent.push(n)
    for (const time of ["18:00", "18:20", "18:45", "19:30", "20:15", "21:00", "21:45", "22:30"])
      tick(db, buildState(db, FRI, at(time)), at(time), send)
    const nags = sent.filter((n) => n.key.startsWith("habit:"))
    expect(nags).toHaveLength(5)
    expect(nags.at(-1)!.urgent).toBe(true)

    store.toggleHabit(db, h, FRI)
    expect(dueNotes(buildState(db, FRI, at("22:40")), at("22:40")).some((n) => n.key.startsWith("habit:"))).toBe(false)
  })

  test("coach asks once", () => {
    const db = fresh()
    const h = store.addHabit(db, { name: "Gym", kind: "check" }, FRI)
    store.setHabitReminder(db, h, "18:00")
    const sent: Note[] = []
    for (const time of ["18:00", "19:00", "20:00"]) tick(db, buildState(db, FRI, at(time)), at(time), (n) => sent.push(n))
    expect(sent.filter((n) => n.key.startsWith("habit:"))).toHaveLength(1)
  })
})

describe("milestones", () => {
  test("reaching 7 days is marked, celebrated once, and grows the flame", () => {
    const db = fresh()
    const h = store.addHabit(db, { name: "Meditate", kind: "check" }, addDays(FRI, -10))
    for (let i = 1; i <= 6; i++) store.toggleHabit(db, h, addDays(FRI, -i))
    expect(buildState(db, FRI, at("09:00")).habits[0]!.milestone).toBeNull()

    store.toggleHabit(db, h, FRI)
    const habit = buildState(db, FRI, at("09:00")).habits[0]!
    expect(habit.streak).toBe(7)
    expect(habit.milestone).toBe(7)
    expect(habit.flame).toBe(1)

    const sent: Note[] = []
    tick(db, buildState(db, FRI, at("09:00")), at("09:00"), (n) => sent.push(n))
    tick(db, buildState(db, FRI, at("09:01")), at("09:01"), (n) => sent.push(n))
    expect(sent.filter((n) => n.key.startsWith("milestone:"))).toHaveLength(1)
    expect(sent.find((n) => n.key.startsWith("milestone:"))!.title).toContain("7")
  })

  test("flame tiers", () => {
    expect([2, 7, 29, 30, 99, 100].map(flameTier)).toEqual([0, 1, 1, 2, 2, 3])
  })
})

describe("notification markup", () => {
  test("names are shown as typed, never as formatting", async () => {
    const { escapeMarkup } = await import("../src/notify")
    expect(escapeMarkup(`<img src="http://x/y.png"> & <b>Gym</b>`)).toBe(`&lt;img src="http://x/y.png"&gt; &amp; &lt;b&gt;Gym&lt;/b&gt;`)
  })
})
