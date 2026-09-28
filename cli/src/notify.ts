import type { Database } from "bun:sqlite"
import { clock, shiftClock } from "./settings"
import { habitLine, line, tone } from "./voice"
import type { State } from "./state"

// `lifeos tick` runs every minute from the bar. It works out which reminders
// are due now and sends each one once: the key goes into `notified` first,
// so several bars (one per monitor) cannot double up.

export interface Note {
  key: string
  title: string
  body: string
  urgent?: boolean
}

export type Sender = (note: Note) => void

export const notifySend: Sender = (note) => {
  try {
    Bun.spawnSync(["notify-send", "--app-name=LifeOS", `--urgency=${note.urgent ? "critical" : "normal"}`, note.title, note.body], {
      stdout: "ignore",
      stderr: "ignore",
    })
  } catch {
    // No notification daemon: reminders are a nicety, never an error.
  }
}

function list(names: string[]): string {
  if (names.length <= 2) return names.join(" and ")
  return `${names.slice(0, 2).join(", ")} and ${names.length - 2} more`
}

const minutes = (t: string) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5))

// Savage mode does not ask once: it asks again every so often until the
// thing is done, a few times at most. Returns which round we are in.
function nagRound(time: string, from: string, every: number, max: number): number {
  const round = Math.floor((minutes(time) - minutes(from)) / every)
  return Math.max(0, Math.min(max, round))
}

// Everything that should have been said by now, most important last so a
// late start does not bury the loud one.
export function dueNotes(state: State, now: Date): Note[] {
  const s = state.settings
  const day = state.today
  const time = clock(now)
  const t = tone(s.tone)
  const nag = t === "savage"
  const notes: Note[] = []
  if (s.notify !== "on" || time < "04:00") return notes
  const plural = (n: number, one: string) => `${n} ${one}${n === 1 ? "" : "s"}`

  if (time >= s.morning) {
    if (!state.day.planned && s.plan === "on") {
      const n = state.summary.tasksLeft
      const key = `plan:${day}`
      notes.push({
        key,
        title: line(t, "planTitle", key, { greeting: state.day.greeting }),
        body: n > 0 ? line(t, "planBody", key, { n: plural(n, "task") }) : line(t, "planBody", key + "none", { n: "Nothing" }),
      })
    }
    for (const e of state.events) {
      const key = `event:${e.id}:${day}`
      if (e.daysLeft === 0) notes.push({ key, title: `${e.emoji ? e.emoji + " " : ""}Today: ${e.title}`, body: "The day is here. Enjoy it." })
      else if (e.daysLeft === 3) notes.push({ key, title: `${e.emoji ? e.emoji + " " : ""}${e.title} in 3 days`, body: "Anything to prepare?" })
    }
    for (const p of state.people) {
      const key = `birthday:${p.id}:${day}`
      const turns = p.turning ? ` turns ${p.turning}` : ""
      if (p.daysLeft === 0) notes.push({ key, title: `🎂 ${p.name}${turns ? turns + " today" : "'s birthday is today"}`, body: "Send them a message." })
      else if (p.daysLeft === 1) notes.push({ key, title: `🎂 ${p.name}${turns ? turns + " tomorrow" : "'s birthday is tomorrow"}`, body: "A gift, a call, a plan?" })
      else if (p.daysLeft === 7) notes.push({ key, title: `🎂 ${p.name}'s birthday in a week`, body: "Time to think of something." })
    }
  }

  // A streak reaching a milestone, the moment it happens.
  for (const h of state.habits) {
    if (!h.milestone) continue
    const key = `milestone:${h.id}:${h.milestone}:${day}`
    notes.push({ key, title: line(t, "milestoneTitle", key, { n: h.milestone, name: h.name }), body: line(t, "milestoneBody", key, {}) })
  }

  // A habit with its own time gets its own nudge while it is still open —
  // once, or in savage mode every 45 minutes, up to five times.
  for (const h of state.habits) {
    if (!h.remindAt || time < h.remindAt || !h.scheduledToday || h.done || h.skipped || h.kind === "avoid") continue
    const round = nag ? nagRound(time, h.remindAt, 45, 4) : 0
    const key = `habit:${h.id}:${day}` + (round ? `:${round}` : "")
    const progress = h.kind === "count" ? ` (${h.value}/${h.target}${h.unit ? " " + h.unit : ""})` : ""
    notes.push({ key, title: h.name + progress, body: habitLine(t, key, h.name), urgent: nag && round >= 2 })
  }

  const left = state.day.habitsLeft
  const lastCall = shiftClock(s.bedtime, -60)
  if (time >= s.remind && left.length > 0 && time < lastCall) {
    const round = nag ? nagRound(time, s.remind, 60, 3) : 0
    const key = `remind:${day}` + (round ? `:${round}` : "")
    // One habit left gets its own kind of line; several get the list.
    notes.push(left.length === 1
      ? { key, title: line(t, "remindTitle", key, { n: "1 habit" }), body: habitLine(t, key, left[0]!) }
      : { key, title: line(t, "remindTitle", key, { n: plural(left.length, "habit") }), body: line(t, "remindBody", key, { list: list(left) }) })
  }

  if (time >= s.shutdown && state.day.needsShutdown) {
    const n = state.day.leftovers.length
    const key = `shutdown:${day}`
    notes.push({ key, title: line(t, "shutdownTitle", key, {}), body: line(t, "shutdownBody", key, { n: plural(n, "unfinished task") }) })
  }

  if (time >= lastCall && left.length > 0) {
    const key = `bedtime:${day}`
    notes.push({ key, title: line(t, "bedtimeTitle", key, {}), body: line(t, "bedtimeBody", key, { list: list(left), time }), urgent: true })
  }

  return notes
}

// Sends what is due and not yet sent. Several reminders about the same
// unfinished habits collapse into the latest, loudest one.
export function tick(db: Database, state: State, now: Date, send: Sender = notifySend): Note[] {
  const pending = dueNotes(state, now).filter((n) => !db.query("SELECT 1 FROM notified WHERE key = ?").get(n.key))
  const claim = db.query("INSERT OR IGNORE INTO notified (key, at) VALUES (?, ?)")
  const sent: Note[] = []
  const habitNotes = pending.filter((n) => n.key.startsWith("remind:") || n.key.startsWith("bedtime:"))
  const loudest = habitNotes[habitNotes.length - 1]

  for (const note of pending) {
    if (claim.run(note.key, now.toISOString()).changes === 0) continue // another bar got there first
    if (habitNotes.includes(note) && note !== loudest) continue
    send(note)
    sent.push(note)
  }
  // Keep the table small: a month of keys is plenty.
  db.query("DELETE FROM notified WHERE at < ?").run(new Date(now.getTime() - 31 * 86_400_000).toISOString())
  return sent
}
