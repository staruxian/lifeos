"""The snapshot is the whole contract with the shell plugin: every number the
panel shows is computed here, so the QML side only lays things out."""

import datetime as dt
import json
import math
import os

import db as dbmod
from dates import add_days, diff_days, from_day, is_scheduled, next_birthday, weekday
from jsmath import js_round, plain
from settings import clock, read_settings, shift_clock
from store import SKIP

HEAT_WEEKS = 18
FIRE_STREAK = 3
# Streaks worth a celebration.
MILESTONES = [7, 14, 30, 50, 100, 200, 365]
PACE_WINDOW = 14


def flame_tier(streak: int) -> int:
    """The flame grows with the streak: 0 below a week, then 1, 2, 3."""
    return 3 if streak >= 100 else 2 if streak >= 30 else 1 if streak >= 7 else 0


# ---- tasks ------------------------------------------------------------------


def build_tasks(db, today: str) -> dict:
    rows = db.all("""
        SELECT id, title, due, done_on, focus_on FROM tasks
        WHERE dropped_on IS NULL AND (done_on IS NULL OR done_on = ?)
        ORDER BY due IS NULL, due, id
    """, today)
    tasks = {"overdue": [], "today": [], "upcoming": [], "someday": [], "doneToday": []}
    for row in rows:
        days_until = diff_days(today, row["due"]) if row["due"] else None
        task = {"id": row["id"], "title": row["title"], "due": row["due"], "daysUntil": days_until,
                "done": row["done_on"] is not None, "focus": row["focus_on"] == today}
        if task["done"]:
            tasks["doneToday"].append(task)
        elif days_until is None:
            tasks["someday"].append(task)
        elif days_until < 0:
            tasks["overdue"].append(task)
        elif days_until == 0:
            tasks["today"].append(task)
        else:
            tasks["upcoming"].append(task)
    return tasks


# ---- habits -----------------------------------------------------------------


def is_done(kind: str, target: int, value: int) -> bool:
    if value == SKIP:
        return False
    if kind == "avoid":
        return value == 0
    return value >= target


def cell_for(h: dict, day: str, today: str, value: int) -> dict:
    """future: not here yet · before: habit did not exist · off: not scheduled
    empty: scheduled, nothing logged · partial / done: count progress
    clean / slip: avoid habits · skip: a skipped day, neither kept nor missed"""
    if day > today:
        return {"day": day, "state": "future", "level": 0, "value": 0}
    if day < h["created_on"]:
        return {"day": day, "state": "before", "level": 0, "value": 0}
    if h["kind"] == "avoid":
        if value > 0:
            return {"day": day, "state": "slip", "level": 0, "value": value}
        return {"day": day, "state": "clean", "level": 4, "value": 0}
    if value == SKIP:
        return {"day": day, "state": "skip", "level": 0, "value": 0}
    if value <= 0:
        return {"day": day, "state": "empty" if is_scheduled(h["days"], day) else "off", "level": 0, "value": 0}
    ratio = min(1, value / h["target"])
    if ratio >= 1:
        return {"day": day, "state": "done", "level": 4, "value": value}
    return {"day": day, "state": "partial", "level": 1 if ratio < 0.34 else 2 if ratio < 0.67 else 3, "value": value}


def streak_for(h: dict, logs: dict, today: str) -> int:
    """Consecutive scheduled days kept, ending today. An unfinished today does
    not break the chain yet. Unscheduled days neither count nor break it.
    Avoid habits count clean days since the last slip."""
    streak = 0
    day = today
    while day >= h["created_on"]:
        value = logs.get(day, 0)
        if h["kind"] == "avoid":
            if value > 0:
                break
            streak += 1
        elif is_scheduled(h["days"], day) and value != SKIP:
            if is_done(h["kind"], h["target"], value):
                streak += 1
            elif day != today:
                break
        day = add_days(day, -1)
    return streak


def rate_for(h: dict, logs: dict, today: str) -> float:
    due = kept = 0
    for i in range(30):
        day = add_days(today, -i)
        if day < h["created_on"]:
            break
        if h["kind"] != "avoid" and not is_scheduled(h["days"], day):
            continue
        if logs.get(day) == SKIP:
            continue
        # Today only counts once it is kept, so the morning does not read as a failure.
        done = is_done(h["kind"], h["target"], logs.get(day, 0))
        if day == today and not done:
            continue
        due += 1
        if done:
            kept += 1
    return 0 if due == 0 else kept / due


def _logs(db, habit_id: int) -> dict:
    return {r["day"]: r["value"] for r in db.all("SELECT day, value FROM habit_logs WHERE habit_id = ?", habit_id)}


def build_habits(db, today: str) -> list[dict]:
    rows = db.all("SELECT id, name, kind, target, unit, days, created_on, remind_at FROM habits ORDER BY position, id")
    grid_start = add_days(today, -weekday(today) - (HEAT_WEEKS - 1) * 7)
    out = []
    for h in rows:
        logs = _logs(db, h["id"])
        heat = [[cell_for(h, d, today, logs.get(d, 0)) for d in (add_days(grid_start, w * 7 + i) for i in range(7))]
                for w in range(HEAT_WEEKS)]
        raw = logs.get(today, 0)
        value = max(0, raw)
        streak = streak_for(h, logs, today)
        week_start = add_days(today, -weekday(today))
        skip_used = False
        day = week_start
        while day < today:
            if logs.get(day) == SKIP:
                skip_used = True
            day = add_days(day, 1)
        done = is_done(h["kind"], h["target"], raw)
        out.append({
            "id": h["id"],
            "name": h["name"],
            "kind": h["kind"],
            "target": h["target"],
            "unit": h["unit"],
            "days": h["days"],
            "scheduledToday": h["kind"] == "avoid" or is_scheduled(h["days"], today),
            "value": value,
            "done": done,
            "progress": min(1, value / h["target"]) if h["kind"] == "count" else (1 if done else 0),
            "streak": streak,
            "onFire": streak >= FIRE_STREAK,
            "flame": flame_tier(streak),
            "milestone": streak if streak in MILESTONES and done else None,
            "rate30": rate_for(h, logs, today),
            "remindAt": h["remind_at"],
            "skipped": raw == SKIP,
            "canSkip": h["kind"] != "avoid" and not skip_used,
            "heat": heat,
        })
    return out


# ---- books ------------------------------------------------------------------


def build_books(db, today: str) -> dict:
    rows = db.all("SELECT id, title, total_pages, created_on, finished_on FROM books ORDER BY id")
    books = []
    for b in rows:
        logs = {}
        read = 0
        for log in db.all("SELECT day, pages FROM reading_logs WHERE book_id = ?", b["id"]):
            logs[log["day"]] = log["pages"]
            read += log["pages"]
        read = min(read, b["total_pages"])
        remaining = b["total_pages"] - read

        first_day = min(logs) if logs else b["created_on"]
        started_on = first_day if first_day < b["created_on"] else b["created_on"]
        window_days = max(1, min(PACE_WINDOW, diff_days(started_on, today) + 1))
        window_pages = 0
        recent = []
        for i in range(PACE_WINDOW - 1, -1, -1):
            day = add_days(today, -i)
            pages = logs.get(day, 0)
            recent.append({"day": day, "pages": pages})
            if i < window_days:
                window_pages += pages
        pace = window_pages / window_days
        if remaining > 0 and pace > 0:
            eta_days = math.ceil(remaining / pace)
        else:
            eta_days = 0 if remaining == 0 else None
        books.append({
            "id": b["id"],
            "title": b["title"],
            "total": b["total_pages"],
            "read": read,
            "remaining": remaining,
            "percent": read / b["total_pages"],
            "today": logs.get(today, 0),
            "pace": js_round(pace * 10) / 10,
            "etaDays": eta_days,
            "etaDay": None if eta_days is None else add_days(today, eta_days),
            "startedOn": started_on,
            "finishedOn": b["finished_on"],
            "recent": recent,
        })

    # Most recently read first: that is the one you will log next.
    def last_read(b):
        return next((r["day"] for r in reversed(b["recent"]) if r["pages"] > 0), b["startedOn"])

    reading = sorted((b for b in books if not b["finishedOn"]), key=lambda b: (last_read(b), b["id"]), reverse=True)
    finished = sorted((b for b in books if b["finishedOn"]), key=lambda b: b["finishedOn"], reverse=True)
    return {"reading": reading, "finished": finished}


# ---- events and people ------------------------------------------------------


def build_events(db, today: str) -> list[dict]:
    """Past events simply stop appearing; the rows stay, so nothing is lost if
    the date was mistyped."""
    out = []
    for e in db.all("SELECT id, title, day, emoji, created_on FROM events WHERE day >= ? ORDER BY day, id", today):
        span = diff_days(e["created_on"], e["day"])
        elapsed = diff_days(e["created_on"], today)
        out.append({
            "id": e["id"],
            "title": e["title"],
            "day": e["day"],
            "emoji": e["emoji"],
            "daysLeft": diff_days(today, e["day"]),
            "progress": 1 if span <= 0 else max(0, min(1, elapsed / span)),
        })
    return out


def build_people(db, today: str) -> list[dict]:
    out = []
    for p in db.all("SELECT id, name, month, day, year FROM people"):
        nxt = next_birthday(p, today)
        out.append({
            "id": p["id"],
            "name": p["name"],
            "month": p["month"],
            "day": p["day"],
            "year": p["year"],
            "next": nxt,
            "daysLeft": diff_days(today, nxt),
            "turning": from_day(nxt).year - p["year"] if p["year"] else None,
        })
    return sorted(out, key=lambda p: (p["daysLeft"], p["name"].casefold(), p["name"]))


# ---- insights -----------------------------------------------------------------

WEEKDAY_PLURALS = ["Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays"]


def longest_run(h: dict, logs: dict, today: str) -> int:
    best = run = 0
    day = h["created_on"]
    while day <= today:
        value = logs.get(day, 0)
        if h["kind"] == "avoid":
            run = 0 if value > 0 else run + 1
        elif is_scheduled(h["days"], day) and value != SKIP:
            if is_done(h["kind"], h["target"], value):
                run += 1
            elif day != today:
                run = 0
        best = max(best, run)
        day = add_days(day, 1)
    return best


def build_insights(db, today: str, habits: list[dict]) -> dict:
    lines = []
    since = add_days(today, -83)  # twelve weeks
    rows = db.all("SELECT id, name, kind, target, unit, days, created_on FROM habits")

    # Promises by weekday, and by day for comparing with mood.
    weekdays = [{"due": 0, "kept": 0} for _ in range(7)]
    per_day: dict[str, dict] = {}
    records = []
    recent = {"due": 0, "kept": 0}
    before = {"due": 0, "kept": 0}

    for h in rows:
        logs = _logs(db, h["id"])
        current = next((x["streak"] for x in habits if x["id"] == h["id"]), 0)
        records.append({"name": h["name"], "best": max(longest_run(h, logs, today), current), "current": current})

        day = since if since > h["created_on"] else h["created_on"]
        while day < today:
            if h["kind"] == "avoid" or is_scheduled(h["days"], day):
                value = logs.get(day, 0)
                if value != SKIP:
                    done = is_done(h["kind"], h["target"], value)
                    w = weekdays[weekday(day)]
                    w["due"] += 1
                    w["kept"] += done
                    d = per_day.setdefault(day, {"due": 0, "kept": 0})
                    d["due"] += 1
                    d["kept"] += done
                    bucket = recent if day >= add_days(today, -30) else before if day >= add_days(today, -60) else None
                    if bucket is not None:
                        bucket["due"] += 1
                        bucket["kept"] += done
            day = add_days(day, 1)

    rated = [{"i": i, "rate": w["kept"] / w["due"] if w["due"] else 0, "due": w["due"]} for i, w in enumerate(weekdays)]
    rated = [w for w in rated if w["due"] >= 3]
    if len(rated) >= 4:
        ordered = sorted(rated, key=lambda w: w["rate"], reverse=True)
        top, low = ordered[0], ordered[-1]
        if top["rate"] - low["rate"] >= 0.15:
            lines.append({"icon": "calendar", "text": f"You keep habits best on {WEEKDAY_PLURALS[top['i']]} ({js_round(top['rate'] * 100)}%) "
                                                      f"and slip most on {WEEKDAY_PLURALS[low['i']]} ({js_round(low['rate'] * 100)}%)."})

    if recent["due"] >= 10 and before["due"] >= 10:
        delta = js_round((recent["kept"] / recent["due"] - before["kept"] / before["due"]) * 100)
        if abs(delta) >= 5:
            lines.append({"icon": "up" if delta > 0 else "down",
                          "text": f"Habits kept are {'up' if delta > 0 else 'down'} {abs(delta)}% on the month before."})

    # Reading: weekdays against weekends.
    reading = db.all("SELECT day, SUM(pages) AS pages FROM reading_logs WHERE day >= ? GROUP BY day", since)
    if len(reading) >= 8:
        wk = wk_days = we = we_days = 0
        for r in reading:
            if weekday(r["day"]) >= 5:
                we += r["pages"]
                we_days += 1
            else:
                wk += r["pages"]
                wk_days += 1
        if wk_days >= 3 and we_days >= 2:
            a, b = wk / wk_days, we / we_days
            ratio = max(a, b) / max(1, min(a, b))
            if ratio >= 1.3:
                lines.append({"icon": "book", "text": f"On reading days you read {'more at weekends' if b > a else 'more on weekdays'}: "
                                                      f"{js_round(b if b > a else a)} pages against {js_round(a if b > a else b)}."})

    # Mood: how kept days feel against the rest.
    checkins = db.all("SELECT day, mood, note FROM days WHERE day >= ? AND mood IS NOT NULL", add_days(today, -89))
    kept, missed = [], []
    for c in checkins:
        d = per_day.get(c["day"])
        if not d or d["due"] == 0:
            continue
        (kept if d["kept"] == d["due"] else missed).append(c["mood"])
    if len(kept) >= 3 and len(missed) >= 3:
        ak, am = sum(kept) / len(kept), sum(missed) / len(missed)
        if abs(ak - am) >= 0.3:
            lines.append({"icon": "mood", "text": f"Days you keep every habit feel {'better' if ak > am else 'harder'}: {ak:.1f} against {am:.1f} out of 5."})

    by_best = sorted(records, key=lambda r: r["best"], reverse=True)
    if by_best and by_best[0]["best"] >= 3:
        r = by_best[0]
        lines.append({"icon": "fire", "text": f"{r['name']} is on its best run ever: {r['best']} days." if r["current"] >= r["best"]
                      else f"Your longest run: {r['name']}, {r['best']} days (now {r['current']})."})

    done = db.one("SELECT COUNT(*) AS n FROM tasks WHERE done_on >= ?", add_days(today, -27))["n"]
    if done >= 4:
        lines.append({"icon": "check", "text": f"You finish about {js_round(done / 4)} tasks a week."})

    by_day = {c["day"]: c for c in checkins}
    mood = []
    for i in range(29, -1, -1):
        day = add_days(today, -i)
        c = by_day.get(day)
        mood.append({"day": day, "mood": c["mood"] if c else None, "note": c["note"] if c else None})

    return {
        "lines": lines,
        "mood": mood,
        "weekdays": [{"rate": w["kept"] / w["due"] if w["due"] else 0, "due": w["due"]} for w in weekdays],
        "records": sorted((r for r in records if r["best"] > 0), key=lambda r: r["best"], reverse=True),
    }


# ---- the week ---------------------------------------------------------------


def build_week(db, start: str, end: str, today: str) -> dict:
    """Promises for a stretch of days: every scheduled habit day (skips excluded,
    avoid habits every day) and every priority set. A promise is kept when the
    habit was done or the priority finished."""
    last = end if end < today else today
    due = kept = 0
    per_day: dict[str, dict] = {}
    rates = []

    for h in db.all("SELECT id, name, kind, target, days, created_on FROM habits"):
        logs = {r["day"]: r["value"] for r in db.all(
            "SELECT day, value FROM habit_logs WHERE habit_id = ? AND day BETWEEN ? AND ?", h["id"], start, last)}
        h_due = h_kept = 0
        day = start
        while day <= last:
            if day >= h["created_on"] and (h["kind"] == "avoid" or is_scheduled(h["days"], day)):
                value = logs.get(day, 0)
                if value != SKIP:
                    done = is_done(h["kind"], h["target"], value)
                    # Today is still being played; only count it once it is won.
                    if not (day == today and not done):
                        h_due += 1
                        h_kept += done
                        d = per_day.setdefault(day, {"due": 0, "kept": 0})
                        d["due"] += 1
                        d["kept"] += done
            day = add_days(day, 1)
        due += h_due
        kept += h_kept
        if h_due >= 2:
            rates.append({"name": h["name"], "rate": h_kept / h_due})

    focus = db.one("""
        SELECT COUNT(*) AS due, COUNT(done_on) AS kept FROM tasks
        WHERE focus_on BETWEEN ? AND ? AND dropped_on IS NULL AND (focus_on < ? OR done_on IS NOT NULL)
    """, start, last, today)
    due += focus["due"]
    kept += focus["kept"]

    rates.sort(key=lambda r: r["rate"], reverse=True)
    tasks_done = db.one("SELECT COUNT(*) AS n FROM tasks WHERE done_on BETWEEN ? AND ?", start, last)["n"]
    pages = db.one("SELECT COALESCE(SUM(pages), 0) AS n FROM reading_logs WHERE day BETWEEN ? AND ?", start, last)["n"]
    perfect = sum(1 for d in per_day.values() if d["due"] > 0 and d["kept"] == d["due"])

    return {
        "start": start,
        "end": end,
        "due": due,
        "kept": kept,
        "rate": 0 if due == 0 else kept / due,
        "perfectDays": perfect,
        "tasksDone": tasks_done,
        "pages": pages,
        "best": rates[0] if rates else None,
        "worst": rates[-1] if len(rates) > 1 and rates[-1]["rate"] < rates[0]["rate"] else None,
    }


# ---- the day ----------------------------------------------------------------

GREETINGS = {"morning": "Good morning", "day": "Good afternoon", "evening": "Good evening", "night": "Late night"}


def phase_for(time: str, settings: dict) -> str:
    if time < "04:00":
        return "night"
    if time < "12:00":
        return "morning"
    if time < settings["shutdown"]:
        return "day"
    if time < settings["bedtime"]:
        return "evening"
    return "night"


def iso(at: dt.datetime) -> str:
    """Date.toISOString(): UTC with milliseconds and a Z."""
    return at.astimezone(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def build_state(db, today: str, now: dt.datetime) -> dict:
    settings = read_settings(db)
    tasks = build_tasks(db, today)
    habits = build_habits(db, today)
    books = build_books(db, today)
    people = build_people(db, today)
    events = build_events(db, today)
    due = [h for h in habits if h["scheduledToday"] and not h["skipped"]]
    current = books["reading"][0] if books["reading"] else None
    time = clock(now)

    day_row = db.one("SELECT planned_at, shutdown_at, mood, note FROM days WHERE day = ?", today) or {}
    planned = bool(day_row.get("planned_at"))
    shutdown = bool(day_row.get("shutdown_at"))
    phase = phase_for(time, settings)
    leftovers = tasks["overdue"] + tasks["today"]
    priorities = [t for t in tasks["overdue"] + tasks["today"] + tasks["upcoming"] + tasks["someday"] + tasks["doneToday"] if t["focus"]]
    habits_left = [h["name"] for h in due if not h["done"]]

    if not habits_left:
        alert = "none"
    elif time >= shift_clock(settings["bedtime"], -60):
        alert = "urgent"
    elif time >= shift_clock(settings["remind"], 120):
        alert = "warn"
    else:
        alert = "none"

    week_start = add_days(today, -weekday(today))
    this_week = build_week(db, week_start, add_days(week_start, 6), today)
    last_week = build_week(db, add_days(week_start, -7), add_days(week_start, -1), today)
    reviewed = (db.one("SELECT value FROM settings WHERE key = 'reviewed'") or {}).get("value")
    any_history = db.one("SELECT COUNT(*) AS n FROM habits WHERE created_on < ?", week_start)["n"] > 0

    tasks_total = len(tasks["overdue"]) + len(tasks["today"]) + len(tasks["doneToday"])
    done_count = sum(1 for h in due if h["done"]) + len(tasks["doneToday"])
    total_count = len(due) + tasks_total

    return {
        "version": 1,
        "generatedAt": iso(now),
        "today": today,
        "summary": {
            "habitsDue": len(due),
            "habitsDone": sum(1 for h in due if h["done"]),
            "tasksLeft": len(leftovers),
            "tasksDoneToday": len(tasks["doneToday"]),
            "overdue": len(tasks["overdue"]),
            "fire": sum(1 for h in habits if h["onFire"]),
            "prioritiesDone": sum(1 for t in priorities if t["done"]),
            "priorities": len(priorities),
            "dayComplete": total_count > 0 and done_count == total_count,
            "nextEvent": events[0] if events else None,
            # Kept apart from events: birthdays belong to People.
            "nextBirthday": people[0] if people else None,
            "reading": {"id": current["id"], "title": current["title"], "percent": current["percent"]} if current else None,
        },
        "tasks": tasks,
        "habits": habits,
        "books": books,
        "events": events,
        "day": {
            "phase": phase,
            "greeting": GREETINGS[phase],
            "planned": planned,
            "shutdown": shutdown,
            "needsPlan": settings["plan"] == "on" and not planned and time >= "04:00" and time < settings["shutdown"],
            "needsShutdown": not shutdown and time >= settings["shutdown"] and len(leftovers) > 0,
            "priorities": priorities,
            "leftovers": leftovers,
            # Unfinished habits get louder as the night goes on.
            "alert": alert,
            "habitsLeft": habits_left,
            "mood": day_row.get("mood"),
            "note": day_row.get("note"),
        },
        "people": people,
        "insights": build_insights(db, today, habits),
        "review": {
            "thisWeek": this_week,
            "lastWeek": last_week,
            "due": any_history and last_week["due"] > 0 and reviewed != last_week["start"],
        },
        "settings": settings,
        # Set when this snapshot follows a change that can be undone.
        "change": None,
    }


def to_json(value) -> str:
    return json.dumps(plain(value), ensure_ascii=False, separators=(",", ":"))


def write_state(state: dict, path: str | None = None) -> None:
    """Written beside, then renamed over, so the plugin's watcher never sees a
    half-written file. The mode applies at creation, so the snapshot is never
    world-readable, not even before the rename."""
    path = path or dbmod.PATHS["state"]
    dbmod.private_dir(os.path.dirname(path))
    tmp = f"{path}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(to_json(state))
    os.replace(tmp, path)
