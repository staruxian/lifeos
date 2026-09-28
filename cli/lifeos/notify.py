"""`lifeos tick` runs every minute from the bar. It works out which reminders
are due now and sends each one once: the key goes into `notified` first, so
several bars (one per monitor) cannot double up."""

import datetime as dt
import subprocess

from settings import clock, shift_clock
from state import iso
from voice import habit_line, line, tone


def escape_markup(text: str) -> str:
    """Notification bodies may be read as markup (the freedesktop spec allows a
    small HTML subset), so text from task, habit and people names is escaped:
    a "<b>" in a name shows as typed, never as formatting or an image."""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def notify_send(note: dict) -> None:
    try:
        subprocess.run(["notify-send", "--app-name=LifeOS", f"--urgency={'critical' if note.get('urgent') else 'normal'}",
                        note["title"], escape_markup(note["body"])],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5, check=False)
    except (OSError, subprocess.SubprocessError):
        pass  # No notification daemon: reminders are a nicety, never an error.


def _list(names: list[str]) -> str:
    if len(names) <= 2:
        return " and ".join(names)
    return f"{', '.join(names[:2])} and {len(names) - 2} more"


def _minutes(t: str) -> int:
    return int(t[:2]) * 60 + int(t[3:5])


def _nag_round(time: str, frm: str, every: int, most: int) -> int:
    """Savage mode asks again every so often until it's done, a few times at most."""
    return max(0, min(most, (_minutes(time) - _minutes(frm)) // every))


def _birthday_title(person: dict, when: str) -> str:
    """ "🎂 Aziz turns 25 tomorrow", or without a birth year "🎂 Aziz's birthday is tomorrow"."""
    if person["turning"]:
        return f"🎂 {person['name']} turns {person['turning']} {when}"
    return f"🎂 {person['name']}'s birthday is {when}"


def _plural(n: int, one: str) -> str:
    return f"{n} {one}{'' if n == 1 else 's'}"


def due_notes(state: dict, now: dt.datetime) -> list[dict]:
    """Everything that should have been said by now, most important last so a
    late start does not bury the loud one."""
    s = state["settings"]
    day = state["today"]
    time = clock(now)
    t = tone(s["tone"])
    nag = t == "savage"
    notes = []
    if s["notify"] != "on" or time < "04:00":
        return notes

    if time >= s["morning"]:
        if not state["day"]["planned"] and s["plan"] == "on":
            n = state["summary"]["tasksLeft"]
            key = f"plan:{day}"
            notes.append({
                "key": key,
                "title": line(t, "planTitle", key, {"greeting": state["day"]["greeting"]}),
                "body": line(t, "planBody", key, {"n": _plural(n, "task")}) if n > 0 else line(t, "planBody", key + "none", {"n": "Nothing"}),
            })
        for e in state["events"]:
            key = f"event:{e['id']}:{day}"
            face = f"{e['emoji']} " if e["emoji"] else ""
            if e["daysLeft"] == 0:
                notes.append({"key": key, "title": f"{face}Today: {e['title']}", "body": "The day is here. Enjoy it."})
            elif e["daysLeft"] == 3:
                notes.append({"key": key, "title": f"{face}{e['title']} in 3 days", "body": "Anything to prepare?"})
        for p in state["people"]:
            key = f"birthday:{p['id']}:{day}"
            if p["daysLeft"] == 0:
                notes.append({"key": key, "title": _birthday_title(p, "today"), "body": "Send them a message."})
            elif p["daysLeft"] == 1:
                notes.append({"key": key, "title": _birthday_title(p, "tomorrow"), "body": "A gift, a call, a plan?"})
            elif p["daysLeft"] == 7:
                notes.append({"key": key, "title": f"🎂 {p['name']}'s birthday in a week", "body": "Time to think of something."})

    # A streak reaching a milestone, the moment it happens.
    for h in state["habits"]:
        if not h["milestone"]:
            continue
        key = f"milestone:{h['id']}:{h['milestone']}:{day}"
        notes.append({"key": key, "title": line(t, "milestoneTitle", key, {"n": h["milestone"], "name": h["name"]}),
                      "body": line(t, "milestoneBody", key, {})})

    # A habit with its own time gets its own nudge while it is still open —
    # once, or in savage mode every 45 minutes, up to five times.
    for h in state["habits"]:
        if not h["remindAt"] or time < h["remindAt"] or not h["scheduledToday"] or h["done"] or h["skipped"] or h["kind"] == "avoid":
            continue
        rnd = _nag_round(time, h["remindAt"], 45, 4) if nag else 0
        key = f"habit:{h['id']}:{day}" + (f":{rnd}" if rnd else "")
        progress = f" ({h['value']}/{h['target']}{' ' + h['unit'] if h['unit'] else ''})" if h["kind"] == "count" else ""
        notes.append({"key": key, "title": h["name"] + progress, "body": habit_line(t, key, h["name"]), "urgent": nag and rnd >= 2})

    left = state["day"]["habitsLeft"]
    last_call = shift_clock(s["bedtime"], -60)
    if time >= s["remind"] and left and time < last_call:
        rnd = _nag_round(time, s["remind"], 60, 3) if nag else 0
        key = f"remind:{day}" + (f":{rnd}" if rnd else "")
        # One habit left gets its own kind of line; several get the list.
        if len(left) == 1:
            notes.append({"key": key, "title": line(t, "remindTitle", key, {"n": "1 habit"}), "body": habit_line(t, key, left[0])})
        else:
            notes.append({"key": key, "title": line(t, "remindTitle", key, {"n": _plural(len(left), "habit")}),
                          "body": line(t, "remindBody", key, {"list": _list(left)})})

    if time >= s["shutdown"] and state["day"]["needsShutdown"]:
        n = len(state["day"]["leftovers"])
        key = f"shutdown:{day}"
        notes.append({"key": key, "title": line(t, "shutdownTitle", key, {}),
                      "body": line(t, "shutdownBody", key, {"n": _plural(n, "unfinished task")})})

    if time >= last_call and left:
        key = f"bedtime:{day}"
        notes.append({"key": key, "title": line(t, "bedtimeTitle", key, {}),
                      "body": line(t, "bedtimeBody", key, {"list": _list(left), "time": time}), "urgent": True})

    return notes


def tick(db, state: dict, now: dt.datetime, send=notify_send) -> list[dict]:
    """Sends what is due and not yet sent. Several reminders about the same
    unfinished habits collapse into the latest, loudest one."""
    pending = [n for n in due_notes(state, now) if not db.one("SELECT 1 AS x FROM notified WHERE key = ?", n["key"])]
    habit_notes = [n for n in pending if n["key"].startswith(("remind:", "bedtime:"))]
    loudest = habit_notes[-1] if habit_notes else None
    sent = []
    for note in pending:
        if db.run("INSERT OR IGNORE INTO notified (key, at) VALUES (?, ?)", note["key"], iso(now)) == 0:
            continue  # another bar got there first
        if note in habit_notes and note is not loudest:
            continue
        send(note)
        sent.append(note)
    # Keep the table small: a month of keys is plenty.
    db.run("DELETE FROM notified WHERE at < ?", iso(now - dt.timedelta(days=31)))
    return sent
