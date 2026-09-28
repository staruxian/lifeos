"""lifeos — tasks, habits, books and countdowns. Run as `python3 path/to/cli/lifeos/lifeos.py`."""

import os
import sys

# Compiled bytecode goes to the user's cache, never into the plugin folder.
sys.pycache_prefix = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "lifeos", "pycache")

import math  # noqa: E402
import re  # noqa: E402

import db as dbmod  # noqa: E402
import output  # noqa: E402
import store  # noqa: E402
from dates import add_days, now as clock_now, parse_birthday, parse_day, parse_weekdays, to_day, weekday  # noqa: E402
from jsmath import js_number, js_round  # noqa: E402
from notify import tick  # noqa: E402
from quick import parse_quick  # noqa: E402
from settings import read_settings, write_setting  # noqa: E402
from state import build_state, iso, to_json, write_state  # noqa: E402
from store import LifeError  # noqa: E402
from undo import capture, save_snapshot, undo  # noqa: E402

BOOLEAN_FLAGS = {"json", "help", "off"}


def parse_args(argv: list[str]) -> tuple[list[str], dict]:
    words: list[str] = []
    flags: dict[str, str] = {}
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--":
            words.extend(argv[i + 1:])
            break
        if arg.startswith("--"):
            name, eq, inline = arg[2:].partition("=")
            if name in BOOLEAN_FLAGS:
                flags[name] = "true"
            elif eq:
                flags[name] = inline
            else:
                i += 1
                if i >= len(argv):
                    raise LifeError(f"--{name} needs a value")
                flags[name] = argv[i]
        elif arg == "-h":
            flags["help"] = "true"
        else:
            words.append(arg)
        i += 1
    return words, flags


def as_id(value: str | None, what: str) -> int:
    n = js_number(value) if value else None
    if n is None or not math.isfinite(n) or not n.is_integer() or n <= 0:
        raise LifeError(f"which {what}? give its number")
    return int(n)


def as_int(value: str | None, what: str) -> int:
    n = js_number(value)
    if value is None or value == "" or n is None or not math.isfinite(n):
        raise LifeError(f"{what} must be a number")
    return js_round(n)


def as_day(value: str, today: str) -> str:
    parsed = parse_day(value, today)
    if not parsed:
        raise LifeError(f'could not understand the date "{value}"')
    return parsed


def optional_day(value: str | None, today: str) -> str | None:
    if value is None:
        return None
    if value.strip().lower() in ("", "none", "someday", "no"):
        return None
    return as_day(value, today)


def as_kind(value: str | None) -> str:
    v = (value or "check").lower()
    if v in ("check", "yes", "yesno"):
        return "check"
    if v in ("count", "amount", "number"):
        return "count"
    if v in ("avoid", "quit", "break"):
        return "avoid"
    raise LifeError("habit kind must be check, count or avoid")


def as_weekdays(value: str | None) -> int | None:
    if value is None:
        return None
    mask = parse_weekdays(value)
    if mask is None:
        raise LifeError(f'could not understand the days "{value}"')
    return mask


def split_due(words: list[str]) -> tuple[str, str | None]:
    """A trailing `due:fri` in a task title is lifted out as the due date."""
    rest, due = [], None
    for w in words:
        m = re.fullmatch(r"due:(.+)", w, re.I | re.S)
        if m:
            due = m.group(1)
        else:
            rest.append(w)
    return " ".join(rest), due


def as_birthday(value: str | None) -> dict:
    parsed = parse_birthday(value) if value else None
    if not parsed:
        raise LifeError('when is the birthday? e.g. --born 12.10.2001 or --born "oct 12"')
    return parsed


def reminder_time(value: str | None):
    """24-hour times like 18:00, or "none" to clear. Returns ... when not given."""
    if value is None:
        return ...
    v = value.strip().lower()
    if v in ("", "none", "off"):
        return None
    m = re.fullmatch(r"(\d{1,2})(?::?(\d{2}))?", v)
    if not m or int(m.group(1)) > 23 or int(m.group(2) or 0) > 59:
        raise LifeError("reminder needs a time like 18:00")
    return f"{m.group(1).rjust(2, '0')}:{(m.group(2) or '00').rjust(2, '0')}"


def quoted(text: str) -> str:
    return f"“{text[:39] + '…' if len(text) > 40 else text}”"


def quiet(state: dict) -> None:
    pass


class Context:
    def __init__(self, db, today: str, now, flags: dict):
        self.db = db
        self.today = today
        self.now = now
        self.flags = flags
        # Set by commands that change data, with the database as it was before.
        self.change: str | None = None
        self.before: bytes | None = None
        # Extra JSON for the caller (the panel), e.g. a quick-add preview.
        self.extra: dict = {}


def changing(ctx: Context, label: str) -> None:
    """Remembers the database for undo and what the change was; main saves both
    once the change has gone through."""
    if ctx.before is None:
        ctx.before = capture(ctx.db)
    ctx.change = label


def log_day(ctx: Context) -> str:
    """Strict mode keeps the record honest: today and yesterday only."""
    on = as_day(ctx.flags["day"], ctx.today) if "day" in ctx.flags else ctx.today
    if on > ctx.today:
        raise LifeError("that day has not happened yet")
    if read_settings(ctx.db)["strict"] == "on" and on < add_days(ctx.today, -1):
        raise LifeError("strict mode: only today and yesterday can be logged")
    return on


def run(ctx: Context, words: list[str]):
    db, today, f = ctx.db, ctx.today, ctx.flags
    group = words[0] if words else ""
    verb = words[1] if len(words) > 1 else ""
    rest = words[2:]

    if group in ("", "today"):
        return output.print_overview
    if group in ("state", "tick"):
        return quiet
    if group == "add":
        return run(ctx, ["task", "add", *words[1:]])
    if group == "read":
        return run(ctx, ["book", "log", f.get("book") or str(store.current_book_id(db)), *words[1:]])

    if group == "quick":
        parsed = parse_quick(" ".join(words[1:]), today)
        if not parsed:
            raise LifeError("type a task, e.g. “pay rent fri”")
        if parsed["kind"] == "read":
            return run(ctx, ["read", str(parsed["pages"])])
        changing(ctx, f"Added {quoted(parsed['title'])}")
        task_id = store.add_task(db, parsed["title"], parsed["due"], today)
        if parsed["focus"]:
            store.set_focus(db, task_id, True, today)
        return output.print_tasks
    if group == "parse":
        ctx.extra["parsed"] = parse_quick(" ".join(words[1:]), today)
        return lambda state: print(to_json(ctx.extra["parsed"]))
    if group == "undo":
        change = undo(db)
        ctx.extra["undone"] = change["label"]
        return lambda state: print(f"Undid: {change['label']}")

    if group in ("task", "tasks"):
        task_id = lambda: as_id(rest[0] if rest else None, "task")  # noqa: E731
        if verb in ("", "ls"):
            return output.print_tasks
        if verb == "add":
            title, due = split_due(rest)
            changing(ctx, f"Added {quoted(title)}")
            store.add_task(db, title, optional_day(f.get("due", due), today), today)
            return output.print_tasks
        if verb == "done":
            changing(ctx, f"Completed {quoted(store.task_title(db, task_id()))}")
            store.set_task_done(db, task_id(), True, today)
            return output.print_tasks
        if verb == "undo":
            changing(ctx, f"Reopened {quoted(store.task_title(db, task_id()))}")
            store.set_task_done(db, task_id(), False, today)
            return output.print_tasks
        if verb == "toggle":
            row = db.one("SELECT done_on FROM tasks WHERE id = ?", task_id())
            changing(ctx, f"{'Reopened' if row and row['done_on'] else 'Completed'} {quoted(store.task_title(db, task_id()))}")
            store.toggle_task(db, task_id(), today)
            return output.print_tasks
        if verb == "due":
            due = optional_day(" ".join(rest[1:]) or "none", today)
            changing(ctx, f"Moved {quoted(store.task_title(db, task_id()))}")
            store.set_task_due(db, task_id(), due)
            return output.print_tasks
        if verb == "rename":
            changing(ctx, f"Renamed {quoted(store.task_title(db, task_id()))}")
            store.rename_task(db, task_id(), " ".join(rest[1:]))
            return output.print_tasks
        if verb == "focus":
            changing(ctx, "Removed a priority" if "off" in f else f"Prioritised {quoted(store.task_title(db, task_id()))}")
            store.set_focus(db, task_id(), "off" not in f, today)
            return output.print_plan
        if verb == "drop":
            changing(ctx, f"Dropped {quoted(store.task_title(db, task_id()))}")
            store.drop_task(db, task_id(), today)
            return output.print_tasks
        if verb == "rm":
            changing(ctx, f"Deleted {quoted(store.task_title(db, task_id()))}")
            store.remove_task(db, task_id())
            return output.print_tasks

    elif group == "plan":
        if verb in ("", "ls"):
            return output.print_plan
        if verb in ("start", "done"):
            changing(ctx, "Planned the day")
            store.mark_planned(db, today, iso(ctx.now))
            return output.print_plan

    elif group == "shutdown":
        changing(ctx, "Shut down the day")
        store.mark_shutdown(db, today, iso(ctx.now))
        return output.print_overview

    elif group == "review":
        if verb == "seen":
            last_week_start = add_days(today, -weekday(today) - 7)
            db.run("INSERT INTO settings (key, value) VALUES ('reviewed', ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value", last_week_start)
            return quiet
        return output.print_week

    elif group in ("set", "settings"):
        if group == "settings" or not verb:
            return output.print_settings
        changing(ctx, f"Changed {verb}")
        write_setting(db, verb, " ".join(rest))
        return output.print_settings

    elif group in ("habit", "habits"):
        habit_id = lambda: as_id(rest[0] if rest else None, "habit")  # noqa: E731
        if verb in ("", "ls"):
            return output.print_habits
        if verb == "add":
            at = reminder_time(f.get("at"))
            changing(ctx, f"Added {quoted(' '.join(rest))}")
            new_id = store.add_habit(db, " ".join(rest), as_kind(f.get("kind")), today,
                                     target=as_int(f["target"], "target") if "target" in f else None,
                                     unit=f.get("unit"), days=as_weekdays(f.get("days")))
            if at is not ... and at:
                store.set_habit_reminder(db, new_id, at)
            return output.print_habits
        if verb == "toggle":
            on = log_day(ctx)
            changing(ctx, f"Logged {quoted(store.habit_name(db, habit_id()))}")
            store.toggle_habit(db, habit_id(), on)
            return output.print_habits
        if verb in ("inc", "dec"):
            on = log_day(ctx)
            by = as_int(rest[1], "amount") if len(rest) > 1 and rest[1] else 1
            changing(ctx, f"Logged {quoted(store.habit_name(db, habit_id()))}")
            store.bump_habit(db, habit_id(), on, by if verb == "inc" else -by)
            return output.print_habits
        if verb == "set":
            on = log_day(ctx)
            changing(ctx, f"Logged {quoted(store.habit_name(db, habit_id()))}")
            store.set_habit_value(db, habit_id(), on, as_int(rest[1] if len(rest) > 1 else None, "value"))
            return output.print_habits
        if verb == "skip":
            on = log_day(ctx)
            start = add_days(on, -weekday(on))
            changing(ctx, f"Skipped {quoted(store.habit_name(db, habit_id()))}")
            store.skip_habit(db, habit_id(), on, start, add_days(start, 6))
            return output.print_habits
        if verb == "edit":
            at = reminder_time(f.get("at"))
            changing(ctx, f"Edited {quoted(store.habit_name(db, habit_id()))}")
            store.update_habit(db, habit_id(), name=f.get("name"),
                               target=as_int(f["target"], "target") if "target" in f else None,
                               unit=f.get("unit"), days=as_weekdays(f.get("days")))
            if at is not ...:
                store.set_habit_reminder(db, habit_id(), at)
            return output.print_habits
        if verb in ("up", "down"):
            changing(ctx, "Reordered habits")
            store.move_habit(db, habit_id(), -1 if verb == "up" else 1)
            return output.print_habits
        if verb == "rm":
            changing(ctx, f"Deleted {quoted(store.habit_name(db, habit_id()))}")
            store.remove_habit(db, habit_id())
            return output.print_habits

    elif group in ("book", "books"):
        book_id = lambda: as_id(rest[0] if rest else None, "book")  # noqa: E731
        if verb in ("", "ls"):
            return output.print_books
        if verb == "add":
            changing(ctx, f"Added {quoted(' '.join(rest))}")
            store.add_book(db, " ".join(rest), as_int(f.get("pages"), "--pages"), today)
            return output.print_books
        if verb == "log":
            on = log_day(ctx)
            changing(ctx, f"Logged pages in {quoted(store.book_title(db, book_id()))}")
            store.log_reading(db, book_id(), as_int(rest[1] if len(rest) > 1 else None, "pages"), on)
            return output.print_books
        if verb == "edit":
            changing(ctx, f"Edited {quoted(store.book_title(db, book_id()))}")
            store.update_book(db, book_id(), title=f.get("title"),
                              total_pages=as_int(f["pages"], "--pages") if "pages" in f else None)
            return output.print_books
        if verb == "rm":
            changing(ctx, f"Deleted {quoted(store.book_title(db, book_id()))}")
            store.remove_book(db, book_id())
            return output.print_books

    elif group in ("event", "events"):
        event_id = lambda: as_id(rest[0] if rest else None, "event")  # noqa: E731
        if verb in ("", "ls"):
            return output.print_events
        if verb == "add":
            if "on" not in f:
                raise LifeError("when is it? add --on <date>")
            on = as_day(f["on"], today)
            changing(ctx, f"Added {quoted(' '.join(rest))}")
            store.add_event(db, " ".join(rest), on, f.get("emoji", ""), today)
            return output.print_events
        if verb == "edit":
            on = as_day(f["on"], today) if "on" in f else None
            changing(ctx, f"Edited {quoted(store.event_title(db, event_id()))}")
            store.update_event(db, event_id(), title=f.get("title"), day=on, emoji=f.get("emoji"))
            return output.print_events
        if verb == "rm":
            changing(ctx, f"Deleted {quoted(store.event_title(db, event_id()))}")
            store.remove_event(db, event_id())
            return output.print_events

    elif group in ("person", "people"):
        person_id = lambda: as_id(rest[0] if rest else None, "person")  # noqa: E731
        if verb in ("", "ls"):
            return output.print_people
        if verb == "add":
            born = as_birthday(f.get("born"))
            changing(ctx, f"Added {quoted(' '.join(rest))}")
            store.add_person(db, " ".join(rest), born, today)
            return output.print_people
        if verb == "edit":
            born = as_birthday(f.get("born")) if "born" in f else None
            changing(ctx, f"Edited {quoted(store.person_name(db, person_id()))}")
            store.update_person(db, person_id(), name=f.get("name"), birthday=born)
            return output.print_people
        if verb == "rm":
            changing(ctx, f"Deleted {quoted(store.person_name(db, person_id()))}")
            store.remove_person(db, person_id())
            return output.print_people

    elif group == "checkin":
        mood = as_int(verb or None, "the day's rating (1–5)")
        changing(ctx, "Checked in")
        store.check_in(db, today, mood, " ".join(rest))
        return output.print_overview

    elif group == "insights":
        return output.print_insights

    elif group == "help":
        return lambda state: print(help_text())

    raise LifeError(f'unknown command "{" ".join(words)}" — try lifeos help')


def help_text() -> str:
    return f"""lifeos — tasks, habits, books and countdowns

  lifeos                              today at a glance
  lifeos add <task> [due:fri]         add a task
  lifeos quick "pay rent fri!"        add like the quick box: a date at the end, ! for a priority
  lifeos task done|undo|rm <n>        finish, reopen or delete a task
  lifeos task due <n> <date|none>     change a due date
  lifeos task rename <n> <title>
  lifeos task focus <n> [--off]       make it one of today's (max 3) priorities
  lifeos task drop <n>                decide against it

  lifeos plan                         today's priorities;  lifeos plan start  marks the day planned
  lifeos shutdown                     close the day (every due task needs a decision first)
  lifeos review                       this week and last: promises kept
  lifeos undo                         undo the last change

  lifeos habit add <name> [--kind check|count|avoid] [--target 8 --unit glasses] [--days mon,wed,fri] [--at 18:00]
  lifeos habit toggle <n>             mark done (check), full (count) or slipped (avoid)
  lifeos habit inc|dec <n> [amount]   count up or down
  lifeos habit skip <n>               skip today — once a week, keeps the streak
  lifeos habit edit <n> [--name] [--target] [--unit] [--days] [--at 18:00|none]
  lifeos habit rm <n>

  lifeos book add <title> --pages 320
  lifeos read <pages> [--book n]      log pages for today
  lifeos book edit <n> [--title] [--pages]
  lifeos book rm <n>

  lifeos event add <title> --on "nov 3" [--emoji ✈️]
  lifeos event edit <n> [--title] [--on] [--emoji]
  lifeos event rm <n>

  lifeos person add <name> --born 12.10.2001    a birthday to count down to (year optional)
  lifeos person edit <n> [--name] [--born]
  lifeos person rm <n>

  lifeos checkin <1-5> [one line]     how the day felt
  lifeos insights                     what the history says

  lifeos set [key value]              settings: strict, plan, morning, remind, shutdown, bedtime, notify, tone
                                      e.g. lifeos set strict on · lifeos set tone savage

  --day <date>   log a habit or reading on another day (strict mode: yesterday at most)
  --json         print the full state as JSON
  dates: today, tomorrow, fri, next mon, in 3 days, 2w, 3.11, nov 3, 2026-11-03

  data:  {dbmod.PATHS["db"]}
  state: {dbmod.PATHS["state"]}"""


def main() -> None:
    # Nothing LifeOS creates — database, its journal files, the snapshot — is
    # for other users' eyes.
    os.umask(0o077)
    json_out = "--json" in sys.argv[1:]
    try:
        words, flags = parse_args(sys.argv[1:])
        if "help" in flags:
            print(help_text())
            return
        db = dbmod.open_db()
        now = clock_now()
        ctx = Context(db, to_day(now), now, flags)
        printer = run(ctx, words)
        if ctx.change and ctx.before is not None:
            save_snapshot(ctx.before, ctx.change, iso(now))
        state = build_state(db, ctx.today, now)
        state["change"] = {"label": ctx.change, "at": iso(now)} if ctx.change else None
        command = words[0] if words else ""
        if command == "tick":
            tick(db, state, now)
        if command != "parse":
            write_state(state)
        db.close()
        if json_out:
            print(to_json({"parsed": ctx.extra.get("parsed")} if command == "parse" else {**state, **ctx.extra}))
        elif command == "state":
            print(to_json(state))
        else:
            printer(state)
    except LifeError as error:
        if json_out:
            print(to_json({"error": str(error)}))
        else:
            print(f"lifeos: {error}", file=sys.stderr)
        sys.exit(1)
    except Exception as error:  # noqa: BLE001 — the panel shows the message, never a traceback
        if json_out:
            print(to_json({"error": str(error)}))
        else:
            print(f"lifeos: {error}", file=sys.stderr)
        sys.exit(1)


main()
