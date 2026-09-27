import type { Database } from "bun:sqlite"
import { LifeError } from "./store"

// Every setting with its default. Times are local "HH:MM".
export const DEFAULTS = {
  // Strict mode: log only today or yesterday, a morning plan and evening
  // shutdown that open on their own, and a typed confirmation before a
  // habit with a streak can be deleted.
  strict: "off",
  // Ask for the day's priorities when the day is not yet planned.
  plan: "on",
  morning: "08:00",
  remind: "20:00",
  shutdown: "21:00",
  bedtime: "23:00",
  notify: "on",
}

export type Settings = typeof DEFAULTS
export type SettingKey = keyof Settings

const TIME_KEYS: SettingKey[] = ["morning", "remind", "shutdown", "bedtime"]
const SWITCH_KEYS: SettingKey[] = ["strict", "plan", "notify"]

export function isSettingKey(key: string): key is SettingKey {
  return key in DEFAULTS
}

export function readSettings(db: Database): Settings {
  const out = { ...DEFAULTS }
  for (const row of db.query("SELECT key, value FROM settings").all() as { key: string; value: string }[])
    if (isSettingKey(row.key)) out[row.key] = row.value
  return out
}

function normalizeTime(value: string): string | null {
  const m = value.trim().match(/^(\d{1,2})(?::?(\d{2}))?$/)
  if (!m) return null
  const h = Number(m[1])
  const min = Number(m[2] ?? 0)
  if (h > 23 || min > 59) return null
  return `${String(h).padStart(2, "0")}:${String(min).padStart(2, "0")}`
}

function normalizeSwitch(value: string): string | null {
  const v = value.trim().toLowerCase()
  if (["on", "true", "yes", "1"].includes(v)) return "on"
  if (["off", "false", "no", "0"].includes(v)) return "off"
  return null
}

export function writeSetting(db: Database, key: string, value: string) {
  if (!isSettingKey(key)) throw new LifeError(`unknown setting "${key}" — one of ${Object.keys(DEFAULTS).join(", ")}`)
  const normalized = TIME_KEYS.includes(key) ? normalizeTime(value) : SWITCH_KEYS.includes(key) ? normalizeSwitch(value) : value
  if (normalized === null) throw new LifeError(TIME_KEYS.includes(key) ? `${key} needs a time like 21:00` : `${key} is on or off`)
  db.query("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value").run(key, normalized)
}

// "HH:MM" of a Date, for comparing against settings.
export function clock(now: Date): string {
  return `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`
}

export function shiftClock(time: string, minutes: number): string {
  const [h, m] = time.split(":").map(Number)
  const total = Math.max(0, Math.min(24 * 60 - 1, h! * 60 + m! + minutes))
  return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`
}
