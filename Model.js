.pragma library

// Pure helpers shared by the bar widget and the panel. The lifeos CLI does
// every calculation; this file only turns its numbers into words.

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var MONTHS_LONG = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
var WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
var WEEKDAYS_LONG = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

function parseDay(day) {
  var p = String(day || "").split("-")
  if (p.length !== 3) return null
  return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
}

function weekdayIndex(date) {
  return (date.getDay() + 6) % 7
}

function longDate(day) {
  var d = parseDay(day)
  if (!d) return ""
  return MONTHS_LONG[d.getMonth()] + " " + d.getDate()
}

function weekdayName(day) {
  var d = parseDay(day)
  return d ? WEEKDAYS_LONG[weekdayIndex(d)] : ""
}

function shortDate(day, withWeekday) {
  var d = parseDay(day)
  if (!d) return ""
  var text = MONTHS[d.getMonth()] + " " + d.getDate()
  return withWeekday ? WEEKDAYS[weekdayIndex(d)] + ", " + text : text
}

function dueLabel(task) {
  if (task.daysUntil === null || task.daysUntil === undefined) return ""
  var n = task.daysUntil
  if (n < -1) return -n + " days late"
  if (n === -1) return "Yesterday"
  if (n === 0) return "Today"
  if (n === 1) return "Tomorrow"
  if (n < 7) return WEEKDAYS_LONG[weekdayIndex(parseDay(task.due))]
  return shortDate(task.due, false)
}

function countdownWord(daysLeft) {
  if (daysLeft === 0) return "Today"
  if (daysLeft === 1) return "Tomorrow"
  return daysLeft + " days"
}

// Short form for the bar: "39d", "2w", "Today".
function countdownShort(daysLeft) {
  if (daysLeft === 0) return "today"
  if (daysLeft === 1) return "1d"
  return daysLeft + "d"
}

function plural(n, one, many) {
  return n + " " + (n === 1 ? one : (many || one + "s"))
}

// "Every day", "Weekdays", "Mon · Wed · Fri"
function daysLabel(mask) {
  if (mask === 127) return "Every day"
  if (mask === 31) return "Weekdays"
  if (mask === 96) return "Weekends"
  var parts = []
  for (var i = 0; i < 7; i++) if (mask & (1 << i)) parts.push(WEEKDAYS[i])
  return parts.join(" · ")
}

function habitDetail(h) {
  if (h.kind === "avoid") {
    if (h.value > 0) return "Slipped today"
    return h.streak === 1 ? "1 day clean" : h.streak + " days clean"
  }
  if (!h.scheduledToday) return "Rest day · " + daysLabel(h.days)
  if (h.kind === "count") return h.value + " of " + h.target + (h.unit ? " " + h.unit : "")
  return h.done ? "Done" : daysLabel(h.days)
}

function percent(fraction) {
  return Math.round(Math.max(0, Math.min(1, fraction || 0)) * 100) + "%"
}

function bookEta(b) {
  if (b.etaDays === null || b.etaDays === undefined) return "Log a few days to see your finish date"
  if (b.etaDays === 0) return "Finished"
  var when = b.etaDays === 1 ? "tomorrow" : b.etaDays < 7 ? "on " + weekdayName(b.etaDay) : "around " + shortDate(b.etaDay, false)
  return "Done " + when + " at " + formatPace(b.pace) + " pages a day"
}

function formatPace(pace) {
  var n = Number(pace) || 0
  return n >= 10 || Math.round(n) === n ? String(Math.round(n)) : n.toFixed(1)
}

// Day progress across habits and today's tasks, for the bar ring.
function dayProgress(summary) {
  if (!summary) return 0
  var total = summary.habitsDue + summary.tasksLeft + summary.tasksDoneToday
  if (total === 0) return 0
  return (summary.habitsDone + summary.tasksDoneToday) / total
}

function cellTooltip(habit, cell) {
  var date = shortDate(cell.day, true)
  switch (cell.state) {
    case "before": return date + " · before you started"
    case "off": return date + " · rest day"
    case "empty": return date + " · missed"
    case "clean": return date + " · clean"
    case "slip": return date + " · slipped"
    case "partial": return date + " · " + cell.value + " of " + habit.target + (habit.unit ? " " + habit.unit : "")
    case "done": return date + (habit.kind === "count" ? " · " + cell.value + (habit.unit ? " " + habit.unit : "") : " · done")
  }
  return date
}

// Common emoji for a new countdown, guessed from its title so a typed event
// never lands without a face. The picker can always override it.
var EMOJI_HINTS = [
  [/birthday|bday|b-day/i, "🎂"], [/trip|flight|travel|vacation|holiday/i, "✈️"],
  [/wedding|anniversary/i, "💍"], [/concert|festival|gig/i, "🎵"], [/exam|test|finals/i, "📝"],
  [/interview|job|work/i, "💼"], [/new year/i, "🎆"], [/party/i, "🎉"], [/game|match/i, "🏟️"],
  [/launch|release|ship/i, "🚀"], [/beach|sea/i, "🏖️"], [/movie|film|cinema/i, "🎬"]
]

var EMOJI_CHOICES = ["🎉", "✈️", "🎂", "💍", "🎵", "🚀", "🏖️", "🎓", "💼", "🏟️", "🎬", "❤️"]

function guessEmoji(title) {
  for (var i = 0; i < EMOJI_HINTS.length; i++) if (EMOJI_HINTS[i][0].test(title)) return EMOJI_HINTS[i][1]
  return ""
}
