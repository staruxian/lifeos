import type { Database } from "bun:sqlite"
import { clock, shiftClock } from "./settings"
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

// Everything that should have been said by now, most important last so a
// late start does not bury the loud one.
export function dueNotes(state: State, now: Date): Note[] {
  const s = state.settings
  const day = state.today
  const time = clock(now)
  const notes: Note[] = []
  if (s.notify !== "on" || time < "04:00") return notes

  if (time >= s.morning) {
    if (!state.day.planned && s.plan === "on") {
      const n = state.summary.tasksLeft
      notes.push({
        key: `plan:${day}`,
        title: `${state.day.greeting} — plan your day`,
        body: n > 0 ? `${n} task${n === 1 ? "" : "s"} due. Pick up to three that matter most.` : "Pick up to three things that matter most today.",
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

  // A habit with its own time gets its own nudge, once, if it is still open.
  for (const h of state.habits) {
    if (!h.remindAt || time < h.remindAt || !h.scheduledToday || h.done || h.skipped || h.kind === "avoid") continue
    notes.push({
      key: `habit:${h.id}:${day}`,
      title: h.name,
      body: h.kind === "count" ? `${h.value} of ${h.target}${h.unit ? " " + h.unit : ""} so far.` : "It's time.",
    })
  }

  const left = state.day.habitsLeft
  if (time >= s.remind && left.length > 0 && time < shiftClock(s.bedtime, -60))
    notes.push({ key: `remind:${day}`, title: `${left.length} habit${left.length === 1 ? "" : "s"} left today`, body: `${list(left)} — there's still time.` })

  if (time >= s.shutdown && state.day.needsShutdown) {
    const n = state.day.leftovers.length
    notes.push({ key: `shutdown:${day}`, title: "Time to shut down", body: `${n} unfinished task${n === 1 ? "" : "s"} need${n === 1 ? "s" : ""} a decision: tomorrow, another day, or drop.` })
  }

  if (time >= shiftClock(s.bedtime, -60) && left.length > 0)
    notes.push({ key: `bedtime:${day}`, title: "Don't break the chain", body: `${list(left)} still open. An hour to go.`, urgent: true })

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
