// Calendar days are plain "YYYY-MM-DD" strings in local time. Everything in
// LifeOS happens on a day, never at an instant, so there is no timezone math
// beyond "what is today here".

export type Day = string

const DAY_MS = 86_400_000

export function toDay(date: Date): Day {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, "0")
  const d = String(date.getDate()).padStart(2, "0")
  return `${y}-${m}-${d}`
}

export function fromDay(day: Day): Date {
  const [y, m, d] = day.split("-").map(Number)
  return new Date(y!, m! - 1, d!)
}

export function today(now = new Date()): Day {
  return toDay(now)
}

export function addDays(day: Day, n: number): Day {
  const date = fromDay(day)
  date.setDate(date.getDate() + n)
  return toDay(date)
}

// Whole days from a to b. Noon anchoring keeps DST shifts from rounding a
// 23- or 25-hour day into the wrong bucket.
export function diffDays(a: Day, b: Day): number {
  const da = fromDay(a)
  const db = fromDay(b)
  da.setHours(12)
  db.setHours(12)
  return Math.round((db.getTime() - da.getTime()) / DAY_MS)
}

// 0 = Monday … 6 = Sunday. The week starts on Monday throughout LifeOS.
export function weekday(day: Day): number {
  return (fromDay(day).getDay() + 6) % 7
}

export function isDay(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  return toDay(fromDay(value)) === value
}

const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

const WEEKDAY_NAMES = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

// Any unambiguous prefix of two letters or more: "tu", "thurs", "friday".
function weekdayIndex(word: string): number {
  const w = word.toLowerCase()
  if (w.length < 2) return -1
  return WEEKDAY_NAMES.findIndex((name) => name.startsWith(w))
}

function monthIndex(word: string): number {
  const w = word.toLowerCase()
  if (w.length < 3) return -1
  return MONTHS.findIndex((name) => w.startsWith(name))
}

// A month/day with no year means the next time that date comes around.
function upcomingDate(base: Day, month: number, dayOfMonth: number): Day | null {
  const year = fromDay(base).getFullYear()
  for (const y of [year, year + 1]) {
    const candidate = new Date(y, month, dayOfMonth)
    if (candidate.getMonth() !== month) return null
    const day = toDay(candidate)
    if (diffDays(base, day) >= 0) return day
  }
  return null
}

function exactDate(year: number, month: number, dayOfMonth: number): Day | null {
  const candidate = new Date(year, month, dayOfMonth)
  if (candidate.getMonth() !== month) return null
  return toDay(candidate)
}

// Understands what people actually type:
//   today, tomorrow, tmr, yesterday
//   mon … sunday, next fri
//   in 3 days, 3d, 2w, +5
//   2026-11-03, 3.11, 03.11.2026, nov 3, 3 nov, november 3 2026
export function parseDay(input: string, base: Day = today()): Day | null {
  const text = input.trim().toLowerCase().replace(/\s+/g, " ")
  if (text === "") return null

  if (isDay(text)) return text
  if (text === "today" || text === "tod") return base
  if (text === "tomorrow" || text === "tmr" || text === "tom") return addDays(base, 1)
  if (text === "yesterday") return addDays(base, -1)

  let m = text.match(/^(?:in )?\+?(\d+) ?(d|day|days|w|wk|week|weeks|m|mo|month|months)?$/)
  if (m && (m[2] || text.startsWith("+") || text.startsWith("in "))) {
    const n = Number(m[1])
    const unit = m[2] ?? "d"
    if (unit.startsWith("w")) return addDays(base, n * 7)
    if (unit.startsWith("m")) {
      const date = fromDay(base)
      date.setMonth(date.getMonth() + n)
      return toDay(date)
    }
    return addDays(base, n)
  }

  m = text.match(/^(next )?([a-z]+)$/)
  if (m) {
    const index = weekdayIndex(m[2]!)
    if (index >= 0) {
      // "fri" is the coming Friday, today included; "next fri" skips today.
      let delta = (index - weekday(base) + 7) % 7
      if (m[1] && delta === 0) delta = 7
      return addDays(base, delta)
    }
  }

  // Day-first numerics, the way most of the world writes them.
  m = text.match(/^(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?$/)
  if (m) {
    const d = Number(m[1])
    const mo = Number(m[2]) - 1
    if (m[3]) {
      const y = Number(m[3].length === 2 ? `20${m[3]}` : m[3])
      return exactDate(y, mo, d)
    }
    return upcomingDate(base, mo, d)
  }

  m = text.match(/^([a-z]+) (\d{1,2})(?:,? (\d{4}))?$/) ?? null
  if (m) {
    const mo = monthIndex(m[1]!)
    if (mo >= 0) return m[3] ? exactDate(Number(m[3]), mo, Number(m[2])) : upcomingDate(base, mo, Number(m[2]))
  }

  m = text.match(/^(\d{1,2}) ([a-z]+)(?:,? (\d{4}))?$/)
  if (m) {
    const mo = monthIndex(m[2]!)
    if (mo >= 0) return m[3] ? exactDate(Number(m[3]), mo, Number(m[1])) : upcomingDate(base, mo, Number(m[1]))
  }

  return null
}

// Scheduled weekdays are a 7-bit mask, bit 0 = Monday.
export const EVERY_DAY = 0b1111111

export function parseWeekdays(input: string): number | null {
  const text = input.trim().toLowerCase()
  if (text === "" || text === "daily" || text === "everyday" || text === "every day") return EVERY_DAY
  if (text === "weekdays") return 0b0011111
  if (text === "weekends") return 0b1100000
  let mask = 0
  for (const part of text.split(/[\s,]+/)) {
    if (!part) continue
    const index = weekdayIndex(part)
    if (index < 0) return null
    mask |= 1 << index
  }
  return mask === 0 ? null : mask
}

export function isScheduled(mask: number, day: Day): boolean {
  return (mask & (1 << weekday(day))) !== 0
}
