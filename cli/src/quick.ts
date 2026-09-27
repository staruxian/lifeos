import { parseDay, type Day } from "./dates"

// What the quick-add box understands:
//   pay rent fri          task, due Friday
//   call mom next mon     task, due next Monday
//   renew passport due:12.10
//   ship the release!     task, one of today's priorities (due today)
//   read 20               log 20 pages to the book you are reading
export type Quick =
  | { kind: "task"; title: string; due: Day | null; focus: boolean }
  | { kind: "read"; pages: number }

export function parseQuick(input: string, today: Day): Quick | null {
  let text = input.trim().replace(/\s+/g, " ")
  if (text === "") return null

  const read = text.match(/^read (\d+)(?: pages?)?$/i)
  if (read) return { kind: "read", pages: Number(read[1]) }

  let focus = false
  if (/!+$/.test(text)) {
    focus = true
    text = text.replace(/\s*!+$/, "")
  } else if (/^!+\s*/.test(text)) {
    focus = true
    text = text.replace(/^!+\s*/, "")
  }

  let due: Day | null = null
  const tagged = text.match(/(?:^|\s)due:(\S+(?:\s\d{1,2})?)$/i)
  if (tagged) {
    due = parseDay(tagged[1]!, today)
    if (due) text = text.slice(0, tagged.index).trim()
  }

  // The longest tail that reads as a date wins: "in 3 days", "next mon", "nov 3", "fri".
  // A date alone is not a task, so at least one word must remain.
  if (!due) {
    const words = text.split(" ")
    for (let n = Math.min(3, words.length - 1); n >= 1; n--) {
      const tail = words.slice(-n).join(" ")
      // Bare numbers and two-letter words ("we", "tu") are too easily just words.
      const day = /^\d+$/.test(tail) || (n === 1 && tail.length < 3) ? null : parseDay(tail, today)
      if (day) {
        due = day
        text = words.slice(0, -n).join(" ")
        // "on fri", "by tomorrow"
        text = text.replace(/\s+(?:on|by|due)$/i, "")
        break
      }
    }
  }

  if (text === "") return null
  if (focus && (!due || due > today)) due = today
  return { kind: "task", title: text, due, focus }
}
