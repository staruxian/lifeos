"""What `lifeos` prints in a terminal."""

import os
import sys

from dates import from_day
from jsmath import js_round

COLOR = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]


def _paint(code):
    return lambda text: f"\x1b[{code}m{text}\x1b[0m" if COLOR else str(text)


dim, bold, green, red, yellow, orange = (_paint(c) for c in ("2", "1", "32", "31", "33", "38;5;208"))


# English names whatever the system language, as the TypeScript CLI printed them.
def short_weekday(day: str) -> str:
    return WEEKDAYS[from_day(day).weekday()][:3]


def month_day(day: str) -> str:
    d = from_day(day)
    return f"{MONTHS[d.month - 1][:3]} {d.day}"


def long_date(day: str) -> str:
    d = from_day(day)
    return f"{WEEKDAYS[d.weekday()]}, {MONTHS[d.month - 1]} {d.day}"


def _due_label(task: dict) -> str:
    n = task["daysUntil"]
    if n is None:
        return ""
    if n < 0:
        return red("yesterday" if n == -1 else f"{-n}d late")
    if n == 0:
        return yellow("today")
    if n == 1:
        return "tomorrow"
    return short_weekday(task["due"]) if n < 7 else month_day(task["due"])


def _task_line(task: dict) -> str:
    box = green("●") if task["done"] else dim("○")
    title = (yellow("★ ") if task["focus"] else "") + (dim(task["title"]) if task["done"] else task["title"])
    due = _due_label(task)
    return f"  {box} {dim(str(task['id']).rjust(3))}  {title}" + (f"  {dim('·')} {due}" if due else "")


def _bar(fraction: float, width: int = 20) -> str:
    filled = js_round(max(0, min(1, fraction)) * width)
    return green("━" * filled) + dim("━" * (width - filled))


HEAT = ["·", "░", "▒", "▓", "█"]


def _heat_cell(cell: dict) -> str:
    state = cell["state"]
    if state == "future":
        return " "
    if state in ("before", "off"):
        return dim("·")
    if state == "slip":
        return red("█")
    if state == "empty":
        return dim("□")
    if state == "skip":
        return dim("–")
    return green(HEAT[cell["level"]])


def _habit_status(h: dict) -> str:
    if h["kind"] == "count":
        return f"{h['value']}/{h['target']}" + (f" {h['unit']}" if h["unit"] else "")
    if h["skipped"]:
        return dim("skipped today")
    if h["kind"] == "avoid":
        return red("slipped") if h["value"] > 0 else green(f"{h['streak']}d clean")
    return green("done") if h["done"] else dim("not yet") if h["scheduledToday"] else dim("rest day")


def _habit_lines(h: dict, with_heat: bool) -> list[str]:
    mark = green("●") if h["done"] else dim("○") if h["scheduledToday"] else dim("-")
    fire = " " + orange(f"🔥 {h['streak']}") if h["onFire"] else ""
    lines = [f"  {mark} {dim(str(h['id']).rjust(3))}  {bold(h['name'])}  {_habit_status(h)}{fire}"]
    if with_heat:
        # Seven rows, Monday at the top, oldest week on the left — as on GitHub.
        for d in range(7):
            lines.append("         " + "".join(_heat_cell(week[d]) for week in h["heat"]))
    return lines


def _num(x) -> str:
    """Numbers as JavaScript prints them: 21, not 21.0."""
    return str(int(x)) if isinstance(x, float) and x.is_integer() else str(x)


def _book_line(b: dict) -> str:
    if b["etaDays"] is None:
        eta = dim("log pages to see a finish date")
    elif b["etaDays"] == 0:
        eta = green("done")
    else:
        eta = dim(f"≈ {b['etaDays']}d at {_num(b['pace'])} p/day")
    today = green(f"+{b['today']} today") if b["today"] > 0 else ""
    return (f"  {dim(str(b['id']).rjust(3))}  {bold(b['title'])}\n"
            f"       {_bar(b['percent'])} {b['read']}/{b['total']}  {js_round(b['percent'] * 100)}%  {eta}  {today}")


def _event_line(e: dict) -> str:
    when = yellow("today!") if e["daysLeft"] == 0 else "tomorrow" if e["daysLeft"] == 1 else f"{bold(e['daysLeft'])} days"
    date = f"{short_weekday(e['day'])}, {month_day(e['day'])}"
    return f"  {e['emoji'] or '◆'}  {dim(str(e['id']).rjust(3))}  {e['title']}  {dim('·')} {when}  {dim(date)}"


def _heading(text: str) -> None:
    print(f"\n{bold(text)}")


def print_tasks(state: dict) -> None:
    t = state["tasks"]
    groups = [("Overdue", t["overdue"]), ("Today", t["today"]), ("Upcoming", t["upcoming"]),
              ("Someday", t["someday"]), ("Done today", t["doneToday"])]
    any_ = False
    for name, tasks in groups:
        if not tasks:
            continue
        any_ = True
        _heading(name)
        for task in tasks:
            print(_task_line(task))
    if not any_:
        print(dim("No tasks. Add one with: lifeos add <task>"))


def print_habits(state: dict) -> None:
    if not state["habits"]:
        print(dim("No habits yet. Add one with: lifeos habit add <name>"))
        return
    _heading("Habits")
    for h in state["habits"]:
        for line in _habit_lines(h, True):
            print(line)


def print_books(state: dict) -> None:
    reading, finished = state["books"]["reading"], state["books"]["finished"]
    if not reading and not finished:
        print(dim("No books yet. Add one with: lifeos book add <title> --pages 320"))
        return
    if reading:
        _heading("Reading")
        for b in reading:
            print(_book_line(b))
    if finished:
        _heading("Finished")
        for b in finished:
            print(f"  {green('✓')} {dim(str(b['id']).rjust(3))}  {b['title']}  {dim(b['finishedOn'])}")


def print_events(state: dict) -> None:
    if not state["events"]:
        print(dim("Nothing to count down to. Add one with: lifeos event add <title> --on <date>"))
        return
    _heading("Coming up")
    for e in state["events"]:
        print(_event_line(e))


def print_overview(state: dict) -> None:
    print(bold(long_date(state["today"])))
    s = state["summary"]

    tasks = state["tasks"]["overdue"] + state["tasks"]["today"] + state["tasks"]["doneToday"]
    if tasks:
        count = f"{s['tasksDoneToday']}/{s['tasksDoneToday'] + s['tasksLeft']}"
        _heading(f"Tasks  {dim(count)}")
        for task in tasks:
            print(_task_line(task))

    due = [h for h in state["habits"] if h["scheduledToday"]]
    if due:
        count = f"{s['habitsDone']}/{s['habitsDue']}"
        _heading(f"Habits  {dim(count)}")
        for h in due:
            for line in _habit_lines(h, False):
                print(line)

    book = state["books"]["reading"][0] if state["books"]["reading"] else None
    if book:
        _heading("Reading")
        print(_book_line(book))

    if state["events"]:
        _heading("Coming up")
        for e in state["events"][:3]:
            print(_event_line(e))

    if not tasks and not due and not book and not state["events"]:
        print(dim("\nA clean slate. Try: lifeos add <task>, lifeos habit add <name>, lifeos help"))


def print_plan(state: dict) -> None:
    d = state["day"]
    count = f"{state['summary']['prioritiesDone']}/{state['summary']['priorities']} · max 3"
    _heading(f"Today's priorities  {dim(count)}")
    if not d["priorities"]:
        print(dim("  None yet. Pick up to three: lifeos task focus <n>"))
    for t in d["priorities"]:
        print(_task_line(t))
    planned = "Day planned." if d["planned"] else "Not planned yet — lifeos plan start when you're set."
    print(dim(f"\n{planned}{' Shut down.' if d['shutdown'] else ''}"))


def _week_line(name: str, w: dict) -> None:
    pct = dim("—") if w["due"] == 0 else bold(f"{js_round(w['rate'] * 100)}%")
    kept = f"promises kept ({w['kept']}/{w['due']})"
    perfect = f"{w['perfectDays']} perfect day{'' if w['perfectDays'] == 1 else 's'}"
    print(f"  {name.ljust(10)} {pct} {dim(kept)}  {perfect}  {w['tasksDone']} tasks  {w['pages']} pages")
    if w["best"]:
        worst = f" · needs love: {w['worst']['name']} {js_round(w['worst']['rate'] * 100)}%" if w["worst"] else ""
        print(dim(f"             best: {w['best']['name']} {js_round(w['best']['rate'] * 100)}%{worst}"))


def print_week(state: dict) -> None:
    _heading("Weekly score")
    _week_line("This week", state["review"]["thisWeek"])
    _week_line("Last week", state["review"]["lastWeek"])


def print_settings(state: dict) -> None:
    _heading("Settings")
    s = state["settings"]
    rows = [
        ("strict", s["strict"], "only today/yesterday can be logged; plan and shutdown open on their own"),
        ("plan", s["plan"], "ask for the day's priorities"),
        ("morning", s["morning"], "plan reminder and countdown news"),
        ("remind", s["remind"], "unfinished habits reminder"),
        ("shutdown", s["shutdown"], "decide on unfinished tasks"),
        ("bedtime", s["bedtime"], "last call an hour before"),
        ("notify", s["notify"], "desktop notifications"),
        ("tone", s["tone"], "gentle · coach · savage (savage nags until it's done)"),
    ]
    for key, value, what in rows:
        print(f"  {key.ljust(9)} {bold(value.ljust(6))} {dim(what)}")
    print(dim("\n  change with: lifeos set <key> <value>"))


def print_people(state: dict) -> None:
    if not state["people"]:
        print(dim("No one yet. Add someone with: lifeos person add <name> --born 12.10.2001"))
        return
    _heading("Birthdays")
    for p in state["people"]:
        n = p["daysLeft"]
        when = yellow("today! 🎂") if n == 0 else "tomorrow" if n == 1 else f"{bold(n)} days"
        age = dim(f" · turns {p['turning']}") if p["turning"] else ""
        print(f"  {dim(str(p['id']).rjust(3))}  {p['name']}  {dim('·')} {when}{age}  {dim(month_day(p['next']))}")


MOODS = ["", "😞", "😕", "😐", "🙂", "😄"]


def print_insights(state: dict) -> None:
    i = state["insights"]
    _heading("Insights")
    if not i["lines"]:
        print(dim("  Not enough history yet — keep logging for a couple of weeks."))
    for line in i["lines"]:
        print(f"  • {line['text']}")
    if any(m["mood"] is not None for m in i["mood"]):
        _heading("Last 30 days")
        print("  " + "".join(MOODS[m["mood"]] if m["mood"] else dim("·") for m in i["mood"]))
