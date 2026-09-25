import type { Book, Cell, Event, Habit, State, Task } from "./state"
import { fromDay } from "./dates"

const color = process.stdout.isTTY && !process.env.NO_COLOR
const paint = (code: string) => (text: string | number) => (color ? `\x1b[${code}m${text}\x1b[0m` : String(text))
const dim = paint("2")
const bold = paint("1")
const green = paint("32")
const red = paint("31")
const yellow = paint("33")
const orange = paint("38;5;208")

function dueLabel(task: Task): string {
  if (task.daysUntil === null) return ""
  if (task.daysUntil < 0) return red(task.daysUntil === -1 ? "yesterday" : `${-task.daysUntil}d late`)
  if (task.daysUntil === 0) return yellow("today")
  if (task.daysUntil === 1) return "tomorrow"
  const date = fromDay(task.due!)
  if (task.daysUntil < 7) return date.toLocaleDateString("en-US", { weekday: "short" })
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric" })
}

function taskLine(task: Task): string {
  const box = task.done ? green("●") : dim("○")
  const title = task.done ? dim(task.title) : task.title
  const due = dueLabel(task)
  return `  ${box} ${dim(String(task.id).padStart(3))}  ${title}${due ? "  " + dim("·") + " " + due : ""}`
}

function bar(fraction: number, width = 20): string {
  const filled = Math.round(Math.max(0, Math.min(1, fraction)) * width)
  return green("━".repeat(filled)) + dim("━".repeat(width - filled))
}

const HEAT = ["·", "░", "▒", "▓", "█"]

function heatCell(cell: Cell): string {
  switch (cell.state) {
    case "future":
      return " "
    case "before":
    case "off":
      return dim("·")
    case "slip":
      return red("█")
    case "empty":
      return dim("□")
    default:
      return green(HEAT[cell.level]!)
  }
}

function habitStatus(h: Habit): string {
  if (h.kind === "count") return `${h.value}/${h.target}${h.unit ? " " + h.unit : ""}`
  if (h.kind === "avoid") return h.value > 0 ? red("slipped") : green(`${h.streak}d clean`)
  return h.done ? green("done") : h.scheduledToday ? dim("not yet") : dim("rest day")
}

function habitLine(h: Habit, withHeat: boolean): string[] {
  const mark = h.done ? green("●") : h.scheduledToday ? dim("○") : dim("-")
  const fire = h.onFire ? " " + orange(`🔥 ${h.streak}`) : ""
  const lines = [`  ${mark} ${dim(String(h.id).padStart(3))}  ${bold(h.name)}  ${habitStatus(h)}${fire}`]
  if (withHeat) {
    // Seven rows, Monday at the top, oldest week on the left — as on GitHub.
    for (let d = 0; d < 7; d++) lines.push("         " + h.heat.map((week) => heatCell(week[d]!)).join(""))
  }
  return lines
}

function bookLine(b: Book): string {
  const eta = b.etaDays === null ? dim("log pages to see a finish date") : b.etaDays === 0 ? green("done") : dim(`≈ ${b.etaDays}d at ${b.pace} p/day`)
  const today = b.today > 0 ? green(`+${b.today} today`) : ""
  return `  ${dim(String(b.id).padStart(3))}  ${bold(b.title)}\n       ${bar(b.percent)} ${b.read}/${b.total}  ${Math.round(b.percent * 100)}%  ${eta}  ${today}`
}

function eventLine(e: Event): string {
  const when = e.daysLeft === 0 ? yellow("today!") : e.daysLeft === 1 ? "tomorrow" : `${bold(e.daysLeft)} days`
  const date = fromDay(e.day).toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" })
  return `  ${e.emoji || "◆"}  ${dim(String(e.id).padStart(3))}  ${e.title}  ${dim("·")} ${when}  ${dim(date)}`
}

function heading(text: string) {
  console.log(`\n${bold(text)}`)
}

export function printTasks(state: State) {
  const t = state.tasks
  const groups: [string, Task[]][] = [
    ["Overdue", t.overdue], ["Today", t.today], ["Upcoming", t.upcoming], ["Someday", t.someday], ["Done today", t.doneToday],
  ]
  let any = false
  for (const [name, tasks] of groups) {
    if (tasks.length === 0) continue
    any = true
    heading(name)
    tasks.forEach((task) => console.log(taskLine(task)))
  }
  if (!any) console.log(dim("No tasks. Add one with: lifeos add <task>"))
}

export function printHabits(state: State) {
  if (state.habits.length === 0) return console.log(dim("No habits yet. Add one with: lifeos habit add <name>"))
  heading("Habits")
  state.habits.forEach((h) => habitLine(h, true).forEach((l) => console.log(l)))
}

export function printBooks(state: State) {
  const { reading, finished } = state.books
  if (reading.length === 0 && finished.length === 0) return console.log(dim("No books yet. Add one with: lifeos book add <title> --pages 320"))
  if (reading.length) {
    heading("Reading")
    reading.forEach((b) => console.log(bookLine(b)))
  }
  if (finished.length) {
    heading("Finished")
    finished.forEach((b) => console.log(`  ${green("✓")} ${dim(String(b.id).padStart(3))}  ${b.title}  ${dim(b.finishedOn!)}`))
  }
}

export function printEvents(state: State) {
  if (state.events.length === 0) return console.log(dim("Nothing to count down to. Add one with: lifeos event add <title> --on <date>"))
  heading("Coming up")
  state.events.forEach((e) => console.log(eventLine(e)))
}

export function printOverview(state: State) {
  const date = fromDay(state.today).toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" })
  console.log(bold(date))
  const s = state.summary

  const tasks = [...state.tasks.overdue, ...state.tasks.today, ...state.tasks.doneToday]
  if (tasks.length) {
    heading(`Tasks  ${dim(`${s.tasksDoneToday}/${s.tasksDoneToday + s.tasksLeft}`)}`)
    tasks.forEach((task) => console.log(taskLine(task)))
  }

  const due = state.habits.filter((h) => h.scheduledToday)
  if (due.length) {
    heading(`Habits  ${dim(`${s.habitsDone}/${s.habitsDue}`)}`)
    due.forEach((h) => habitLine(h, false).forEach((l) => console.log(l)))
  }

  const book = state.books.reading[0]
  if (book) {
    heading("Reading")
    console.log(bookLine(book))
  }

  if (state.events.length) {
    heading("Coming up")
    state.events.slice(0, 3).forEach((e) => console.log(eventLine(e)))
  }

  if (!tasks.length && !due.length && !book && !state.events.length)
    console.log(dim("\nA clean slate. Try: lifeos add <task>, lifeos habit add <name>, lifeos help"))
}
