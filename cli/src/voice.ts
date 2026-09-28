// How LifeOS talks in notifications. Three tones:
//   gentle — calm and short
//   coach  — a pep talk
//   savage — a friend who roasts you until you move
// Lines are picked by the notification's key, so each reminder keeps its
// wording but tomorrow's is different.

export type Tone = "gentle" | "coach" | "savage"
export const TONES: Tone[] = ["gentle", "coach", "savage"]

type Topic = "fitness" | "reading" | "water" | "mind" | "study" | "general"

const TOPICS: [Topic, RegExp][] = [
  ["fitness", /gym|work ?out|run|jog|push.?up|pull.?up|squat|exercise|train|walk|steps|yoga|lift|cardio|swim|bike|cycl|stretch|sport|abs|plank/i],
  ["reading", /read|book|page|chapter/i],
  ["water", /water|drink|hydrat|glass/i],
  ["mind", /meditat|breath|journal|pray|mindful|gratitude|calm/i],
  ["study", /study|learn|practi|homework|math|physics|chem|biolog|code|coding|language|revis|exam|lesson|notes/i],
]

export function topicOf(name: string): Topic {
  for (const [topic, re] of TOPICS) if (re.test(name)) return topic
  return "general"
}

// {name} the habit, {n} a number, {list} habit names, {time} the clock.
const HABIT: Record<Tone, Record<Topic, string[]>> = {
  gentle: {
    fitness: ["Time for {name}.", "{name} is up next."],
    reading: ["A few pages of {name}?", "Time for {name}."],
    water: ["Time for a glass of water.", "{name}: a sip now helps."],
    mind: ["A quiet moment for {name}.", "Time for {name}."],
    study: ["Time for {name}.", "{name} — a short session counts."],
    general: ["Time for {name}.", "{name} is still open."],
  },
  coach: {
    fitness: [
      "One rep at a time. {name} is waiting — you've got this.",
      "Champions train on the days they don't feel like it. {name} time.",
      "Ten minutes in and you'll be glad you went. {name}, let's go.",
      "Your future self is already proud. Go earn it: {name}.",
    ],
    reading: [
      "Ten pages today, a new mind in a year. {name}, let's go.",
      "Readers are leaders. Open {name}.",
      "One chapter. You've got time for one chapter.",
    ],
    water: ["Hydrated brain, sharper you. Drink up.", "Water first, everything else after. Glass up."],
    mind: ["Two minutes of calm beats an hour of stress. {name}.", "Breathe in, show up. {name} time."],
    study: ["Small sessions build big results. {name}, 25 minutes.", "Future you passes because present you studied. {name}."],
    general: ["Keep the promise you made to yourself: {name}.", "Show up for {name}. That's all it takes."],
  },
  savage: {
    fitness: [
      "Get your freaking ass up and go touch some grass. {name} won't do itself.",
      "Your muscles filed a missing person report. {name}. Now.",
      "The couch is winning. Unacceptable. {name}, go.",
      "You said you'd do {name}. Were you lying? Prove me wrong.",
      "Scrolling burns zero calories. Shoes on. {name}.",
      "Even your phone is tired of watching you sit. {name}!",
    ],
    reading: [
      "Your book is collecting dust and so is your brain. {name}, go.",
      "TikTok won't make you smarter. {name}. Ten pages. Now.",
      "The pages aren't going to read themselves, genius.",
    ],
    water: [
      "You're basically a raisin right now. Drink. Water.",
      "Your plants get watered more than you. Fix it.",
      "Hydrate or diedrate. Glass. Now.",
    ],
    mind: [
      "Sit down, shut up, breathe. {name}. Ten minutes.",
      "Your brain has 47 tabs open. Close them. {name}.",
    ],
    study: [
      "Future you is begging. Open the notes. {name}.",
      "The exam doesn't care about your vibes. {name}, now.",
      "You're not 'taking a break', you're procrastinating. {name}.",
    ],
    general: [
      "Still haven't done {name}? Bold strategy. Go.",
      "{name}. You. Now. No excuses.",
      "Discipline is doing {name} even when you don't want to. So do it.",
    ],
  },
}

const LINES: Record<Tone, Record<string, string[]>> = {
  gentle: {
    planTitle: ["{greeting} — plan your day"],
    planBody: ["{n} due. Pick up to three that matter most.", "Pick up to three things that matter most today."],
    remindTitle: ["{n} left today"],
    remindBody: ["{list} — there's still time."],
    bedtimeTitle: ["Don't break the chain"],
    bedtimeBody: ["{list} still open. An hour to go."],
    shutdownTitle: ["Time to shut down"],
    shutdownBody: ["{n} need a decision: tomorrow, another day, or drop."],
    milestoneTitle: ["🔥 {n} days of {name}"],
    milestoneBody: ["A real streak. Well done."],
  },
  coach: {
    planTitle: ["{greeting}, let's win today", "{greeting}! Plan the day"],
    planBody: ["{n} on deck. Choose your three big ones and attack.", "Three priorities. Clear head. Let's go."],
    remindTitle: ["{n} left — finish strong"],
    remindBody: ["{list}. You're closer than you think.", "{list}. Close the day like a pro."],
    bedtimeTitle: ["Last call, champ"],
    bedtimeBody: ["{list} still open. One hour. Protect that streak.", "{list}. Finish what you started — one hour left."],
    shutdownTitle: ["Close the day like a pro"],
    shutdownBody: ["{n} to decide. Give each a place and rest easy."],
    milestoneTitle: ["🔥 {n} days of {name}!", "🏆 {n}-day streak: {name}"],
    milestoneBody: ["That's not luck, that's who you are now.", "Consistency is a superpower. You have it."],
  },
  savage: {
    planTitle: ["Wake up. Plan your day.", "{greeting}. The day won't plan itself."],
    planBody: ["{n} waiting. Pick three before the day picks for you.", "Three priorities. Not seven. Three. Go."],
    remindTitle: ["{n} still open. Really?", "Hello?? {n} left"],
    remindBody: ["{list}. Stop scrolling and do it.", "{list}. You have time. You just don't have excuses."],
    bedtimeTitle: ["You're really gonna let the streak die?", "Streak on life support"],
    bedtimeBody: ["{list} still open and it's {time}. Excuses don't count as reps.", "{list}. One hour. Move or explain yourself to tomorrow."],
    shutdownTitle: ["Your tasks are rotting"],
    shutdownBody: ["{n} just sitting there. Decide or drop them, chief.", "{n} left undecided. Clean it up before bed."],
    milestoneTitle: ["🔥 {n} days of {name}", "🏆 {n} days. Who even are you?"],
    milestoneBody: ["Okay, fine. You're actually kinda built different.", "Look at you, not quitting. Keep going."],
  },
}

function hash(text: string): number {
  let h = 2166136261
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619)
  return Math.abs(h)
}

function fill(template: string, vars: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (_, k: string) => (k in vars ? String(vars[k]) : `{${k}}`))
}

export function pick(key: string, options: string[], vars: Record<string, string | number>): string {
  return fill(options[hash(key) % options.length]!, vars)
}

export function tone(value: string): Tone {
  return (TONES as string[]).includes(value) ? (value as Tone) : "coach"
}

export function habitLine(t: Tone, key: string, name: string): string {
  return pick(key, HABIT[t][topicOf(name)], { name })
}

export function line(t: Tone, what: string, key: string, vars: Record<string, string | number>): string {
  return pick(key + what, LINES[t][what]!, vars)
}
